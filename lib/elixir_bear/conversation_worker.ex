defmodule ElixirBear.ConversationWorker do
  @moduledoc """
  GenServer that handles LLM inference for a conversation in the background.

  This worker:
  - Manages streaming responses from LLM providers
  - Broadcasts updates via PubSub to all subscribers
  - Persists the final message to the database
  - Survives conversation switches in the UI
  """
  use GenServer
  require Logger

  alias ElixirBear.{Chat, OpenAI, Ollama}

  @doc """
  Starts a conversation worker.

  ## Options
  - `:conversation_id` - The conversation ID
  - `:messages` - List of messages to send to LLM
  - `:user_message_id` - ID of the user's message that triggered this
  """
  def start_link(opts) do
    conversation_id = Keyword.fetch!(opts, :conversation_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(conversation_id))
  end

  @doc """
  Starts inference for a conversation.
  Returns {:ok, pid} if worker started, or {:error, reason} if already running.
  """
  def start_inference(conversation_id, messages, user_message_id) do
    case DynamicSupervisor.start_child(
           ElixirBear.ConversationWorkerSupervisor,
           {__MODULE__,
            conversation_id: conversation_id,
            messages: messages,
            user_message_id: user_message_id}
         ) do
      {:ok, pid} ->
        GenServer.cast(pid, :start_streaming)
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        {:error, :already_running}

      error ->
        error
    end
  end

  @doc """
  Stops the worker for a conversation.
  """
  def stop_worker(conversation_id) do
    case GenServer.whereis(via_tuple(conversation_id)) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(ElixirBear.ConversationWorkerSupervisor, pid)
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    conversation_id = Keyword.fetch!(opts, :conversation_id)
    messages = Keyword.fetch!(opts, :messages)
    user_message_id = Keyword.fetch!(opts, :user_message_id)

    state = %{
      conversation_id: conversation_id,
      messages: messages,
      user_message_id: user_message_id,
      content_buffer: "",
      status: :idle
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:start_streaming, state) do
    # Broadcast that streaming started
    broadcast(state.conversation_id, {:streaming_started, state.user_message_id})

    # Get worker PID to send messages back to
    worker_pid = self()

    # Start the streaming task
    task =
      Task.async(fn ->
        stream_from_llm(worker_pid, state.conversation_id, state.messages)
      end)

    {:noreply, Map.put(state, :task, task) |> Map.put(:status, :streaming)}
  end

  @impl true
  def handle_info({:stream_chunk, chunk}, state) do
    Logger.debug("Received chunk of #{String.length(chunk)} bytes")

    # Append chunk to buffer
    new_content = state.content_buffer <> chunk

    # Broadcast the update
    broadcast(state.conversation_id, {:content_update, new_content})

    {:noreply, %{state | content_buffer: new_content}}
  end

  @impl true
  def handle_info({:stream_complete}, state) do
    # Only save if we have content
    if state.content_buffer != "" do
      # Save the final message to database
      case Chat.create_message(%{
             conversation_id: state.conversation_id,
             role: "assistant",
             content: state.content_buffer
           }) do
        {:ok, message} ->
          # Ensure attachments is an empty list (assistant messages have no attachments)
          message_with_attachments = %{message | attachments: []}
          broadcast(state.conversation_id, {:streaming_complete, message_with_attachments})
          # Stop the worker after completion
          {:stop, :normal, state}

        {:error, reason} ->
          Logger.error("Failed to save assistant message: #{inspect(reason)}")
          broadcast(state.conversation_id, {:streaming_error, "Failed to save message"})
          {:stop, :normal, state}
      end
    else
      # No content received
      Logger.warning("Stream completed with no content for conversation #{state.conversation_id}")
      broadcast(state.conversation_id, {:streaming_error, "No response received from LLM"})
      {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:stream_error, reason}, state) do
    Logger.error("Streaming error for conversation #{state.conversation_id}: #{inspect(reason)}")
    broadcast(state.conversation_id, {:streaming_error, reason})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Task completed, ignore the result message
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Task process went down, we handle completion via :stream_complete
    {:noreply, state}
  end

  ## Private Functions

  defp stream_from_llm(worker_pid, _conversation_id, llm_messages) do
    callback = fn chunk ->
      send(worker_pid, {:stream_chunk, chunk})
    end

    # Get settings
    llm_provider = Chat.get_setting_value("llm_provider") || "ollama"
    api_key = Chat.get_setting_value("openai_api_key") || ""
    ollama_url = Chat.get_setting_value("ollama_url") || "http://localhost:11434"

    # Get model based on provider
    model =
      case llm_provider do
        "ollama" -> Chat.get_setting_value("ollama_model") || "llama3.2"
        "openai" -> Chat.get_setting_value("openai_model") || "gpt-4o-mini"
        _ -> "gpt-4o-mini"
      end

    Logger.info("Starting LLM stream - Provider: #{llm_provider}, Model: #{model}, Messages: #{length(llm_messages)}")

    # Check if any message has images (requires OpenAI Vision)
    has_images =
      Enum.any?(llm_messages, fn msg ->
        is_list(msg["content"]) and
          Enum.any?(msg["content"], fn part -> part["type"] == "image_url" end)
      end)

    # Select provider and stream
    result =
      cond do
        has_images ->
          # Force OpenAI for vision
          vision_model = Chat.get_setting_value("openai_vision_model") || "gpt-4o"
          OpenAI.stream_chat_completion(api_key, llm_messages, callback, model: vision_model)

        llm_provider == "openai" ->
          OpenAI.stream_chat_completion(api_key, llm_messages, callback, model: model)

        llm_provider == "ollama" ->
          Ollama.stream_chat_completion(llm_messages, callback, model: model, url: ollama_url)

        true ->
          {:error, "Unknown LLM provider: #{llm_provider}"}
      end

    case result do
      :ok ->
        Logger.info("LLM stream completed successfully")
        send(worker_pid, {:stream_complete})

      {:error, reason} ->
        Logger.error("LLM stream failed: #{inspect(reason)}")
        send(worker_pid, {:stream_error, reason})
    end
  end

  defp broadcast(conversation_id, message) do
    Phoenix.PubSub.broadcast(
      ElixirBear.PubSub,
      "conversation:#{conversation_id}",
      {__MODULE__, message}
    )
  end

  defp via_tuple(conversation_id) do
    {:via, Registry, {ElixirBear.ConversationWorkerRegistry, conversation_id}}
  end
end
