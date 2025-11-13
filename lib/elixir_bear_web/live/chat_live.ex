defmodule ElixirBearWeb.ChatLive do
  use ElixirBearWeb, :live_view

  alias ElixirBear.{Chat, Ollama, OpenAI}

  @impl true
  def mount(_params, _session, socket) do
    conversations = Chat.list_conversations()
    selected_background = Chat.get_selected_background_image()

    socket =
      socket
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, nil)
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> assign(:selected_background, selected_background)
      |> allow_upload(:message_files,
        accept: ~w(.jpg .jpeg .png .gif .webp .mp3 .mp4 .mpeg .mpga .m4a .wav
                   .txt .md .ex .exs .heex .eex .leex
                   .js .jsx .ts .tsx .css .scss .html .json .xml .yaml .yml .toml
                   .py .rb .java .go .rs .c .cpp .h .hpp .sh .bash),
        max_entries: 10,
        max_file_size: 20_000_000  # 20MB
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    conversation = Chat.get_conversation!(id)
    messages = Chat.list_messages(id)

    socket =
      socket
      |> assign(:current_conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:error, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    system_prompt = Chat.get_setting_value("system_prompt") || ""

    case Chat.create_conversation(%{title: "New Conversation", system_prompt: system_prompt}) do
      {:ok, conversation} ->
        conversations = Chat.list_conversations()

        socket =
          socket
          |> assign(:conversations, conversations)
          |> push_navigate(to: ~p"/chat/#{conversation.id}")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create conversation")}
    end
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => id}, socket) do
    conversation = Chat.get_conversation!(id)
    {:ok, _} = Chat.delete_conversation(conversation)

    conversations = Chat.list_conversations()

    socket =
      if socket.assigns.current_conversation &&
           socket.assigns.current_conversation.id == String.to_integer(id) do
        socket
        |> assign(:conversations, conversations)
        |> assign(:current_conversation, nil)
        |> assign(:messages, [])
        |> push_navigate(to: ~p"/")
      else
        assign(socket, :conversations, conversations)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if message == "" do
      {:noreply, socket}
    else
      send_message(socket, message)
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input, message)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :message_files, ref)}
  end

  @impl true
  def handle_info({:stream_content, content}, socket) do
    # Update the last message (assistant's response) with new content
    messages = socket.assigns.messages

    updated_messages =
      case List.last(messages) do
        %{role: "assistant"} ->
          List.update_at(messages, -1, fn msg ->
            %{msg | content: msg.content <> content}
          end)

        _ ->
          messages
      end

    {:noreply, assign(socket, :messages, updated_messages)}
  end

  @impl true
  def handle_info({:stream_complete}, socket) do
    # Get the final content from the last message (the accumulated assistant response)
    final_content =
      case List.last(socket.assigns.messages) do
        %{role: "assistant", content: content} -> content
        _ -> ""
      end

    # Save the complete assistant message only if we have content
    conversation = socket.assigns.current_conversation

    result =
      if final_content != "" do
        Chat.create_message(%{
          conversation_id: conversation.id,
          role: "assistant",
          content: final_content
        })
      else
        {:error, "No content received"}
      end

    case result do
      {:ok, _message} ->
        # Update conversation title if it's the first message
        if length(socket.assigns.messages) == 2 do
          title = Chat.generate_conversation_title(conversation.id)
          {:ok, updated_conversation} = Chat.update_conversation(conversation, %{title: title})
          conversations = Chat.list_conversations()

          socket =
            socket
            |> assign(:current_conversation, updated_conversation)
            |> assign(:conversations, conversations)
            |> assign(:loading, false)

          {:noreply, socket}
        else
          {:noreply, assign(socket, :loading, false)}
        end

      {:error, _reason} ->
        # Remove the temporary assistant message if save failed
        messages =
          socket.assigns.messages
          |> Enum.reject(fn msg -> msg.role == "assistant" && !Map.has_key?(msg, :id) end)

        socket =
          socket
          |> assign(:messages, messages)
          |> assign(:loading, false)
          |> assign(:error, "Failed to save response. Please try again.")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:error, error_message}, socket) do
    # Remove the temporary assistant message
    messages =
      socket.assigns.messages
      |> Enum.reject(fn msg -> msg.role == "assistant" && !Map.has_key?(msg, :id) end)

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:loading, false)
      |> assign(:error, error_message)

    {:noreply, socket}
  end

  defp send_message(socket, user_message) do
    conversation = socket.assigns.current_conversation
    llm_provider = Chat.get_setting_value("llm_provider") || "openai"

    cond do
      is_nil(conversation) ->
        {:noreply, put_flash(socket, :error, "Please create a conversation first")}

      llm_provider == "openai" && !valid_openai_config?() ->
        {:noreply, put_flash(socket, :error, "Please set your OpenAI API key in settings")}

      llm_provider == "ollama" && !valid_ollama_config?() ->
        {:noreply, put_flash(socket, :error, "Ollama is not running or configured correctly")}

      true ->
        # Save user message
        {:ok, _message} =
          Chat.create_message(%{
            conversation_id: conversation.id,
            role: "user",
            content: user_message
          })

        # Add user message to display
        messages = socket.assigns.messages ++ [%{role: "user", content: user_message}]

        # Add temporary assistant message
        messages = messages ++ [%{role: "assistant", content: ""}]

        socket =
          socket
          |> assign(:messages, messages)
          |> assign(:input, "")
          |> assign(:loading, true)
          |> assign(:error, nil)

        # Prepare messages for LLM (exclude the temporary empty assistant message)
        system_prompt = Chat.get_system_prompt(conversation)

        # Filter out empty messages (like the temporary assistant message we just added)
        filtered_messages =
          socket.assigns.messages
          |> Enum.reject(fn msg -> msg.role == "assistant" && msg.content == "" end)

        llm_messages =
          if system_prompt && system_prompt != "" do
            [%{role: "system", content: system_prompt}] ++
              Enum.map(filtered_messages, fn msg ->
                %{role: msg.role, content: msg.content}
              end)
          else
            Enum.map(filtered_messages, fn msg ->
              %{role: msg.role, content: msg.content}
            end)
          end

        # Start async task to call LLM with streaming
        parent = self()

        Task.start(fn ->
          callback = fn chunk ->
            send(parent, {:stream_content, chunk})
          end

          result =
            case llm_provider do
              "openai" ->
                api_key = Chat.get_setting_value("openai_api_key")
                model = Chat.get_setting_value("openai_model") || "gpt-3.5-turbo"
                OpenAI.stream_chat_completion(api_key, llm_messages, callback, model: model)

              "ollama" ->
                model = Chat.get_setting_value("ollama_model") || "codellama:latest"
                url = Chat.get_setting_value("ollama_url") || "http://localhost:11434"
                Ollama.stream_chat_completion(llm_messages, callback, model: model, url: url)

              _ ->
                {:error, "Unknown LLM provider: #{llm_provider}"}
            end

          case result do
            :ok ->
              # Stream completed successfully, signal completion
              send(parent, {:stream_complete})

            {:error, reason} ->
              send(parent, {:error, reason})
          end
        end)

        {:noreply, socket}
    end
  end

  defp valid_openai_config? do
    api_key = Chat.get_setting_value("openai_api_key")
    !is_nil(api_key) && api_key != ""
  end

  defp valid_ollama_config? do
    url = Chat.get_setting_value("ollama_url") || "http://localhost:11434"

    case Ollama.check_connection(url: url) do
      {:ok, _version} -> true
      {:error, _} -> false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-200">
      <!-- Sidebar -->
      <div class="w-64 bg-base-300 text-base-content flex flex-col">
        <div class="p-4">
          <button
            phx-click="new_conversation"
            class="w-full px-4 py-2 bg-primary hover:bg-primary/90 text-primary-content rounded-lg font-medium transition-colors"
          >
            + New Conversation
          </button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= for conversation <- @conversations do %>
            <div class="group relative">
              <.link
                navigate={~p"/chat/#{conversation.id}"}
                class={[
                  "block px-4 py-3 hover:bg-base-100 cursor-pointer transition-colors pr-10",
                  @current_conversation && @current_conversation.id == conversation.id &&
                    "bg-base-100"
                ]}
              >
                <span class="text-sm truncate block">{conversation.title}</span>
              </.link>
              <button
                phx-click="delete_conversation"
                phx-value-id={conversation.id}
                class="absolute right-2 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 p-1 text-error hover:text-error/80 transition-opacity z-10"
              >
                <svg
                  class="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  xmlns="http://www.w3.org/2000/svg"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                  >
                  </path>
                </svg>
              </button>
            </div>
          <% end %>
        </div>

        <div class="p-4 border-t border-base-100">
          <.link
            navigate={~p"/settings"}
            class="flex items-center gap-2 px-4 py-2 hover:bg-base-100 rounded-lg transition-colors"
          >
            <svg
              class="w-5 h-5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              >
              </path>
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              >
              </path>
            </svg>
            Settings
          </.link>
        </div>
      </div>
      <!-- Main Chat Area -->
      <div class="flex-1 flex flex-col">
        <%= if @current_conversation do %>
          <!-- Messages -->
          <div
            class="flex-1 overflow-y-auto p-6 space-y-4 bg-cover bg-center bg-no-repeat"
            style={
              if @selected_background do
                "background-image: linear-gradient(rgba(0, 0, 0, 0.3), rgba(0, 0, 0, 0.3)), url('#{@selected_background.file_path}');"
              else
                ""
              end
            }
          >
            <%= if @error do %>
              <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
                <p class="font-bold">Error</p>
                <p>{@error}</p>
              </div>
            <% end %>

            <%= for message <- @messages do %>
              <div class={[
                "flex gap-4",
                message.role == "user" && "justify-end"
              ]}>
                <div class={[
                  "max-w-3xl rounded-lg px-4 py-3",
                  message.role == "user" && "bg-primary text-primary-content",
                  message.role == "assistant" && "bg-base-100 text-base-content shadow"
                ]}>
                  <div class="text-sm font-medium mb-1">
                    {if message.role == "user", do: "You", else: "ElixirBear"}
                  </div>
                  <div class="whitespace-pre-wrap">{message.content}</div>
                </div>
              </div>
            <% end %>

            <%= if @loading do %>
              <div class="flex gap-4">
                <div class="bg-base-100 text-base-content shadow rounded-lg px-4 py-3">
                  <div class="flex items-center gap-2">
                    <div class="animate-pulse">Thinking...</div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
          <!-- Input Area -->
          <div class="border-t border-base-300 bg-base-100 p-4">
            <!-- File Upload Previews -->
            <%= if length(@uploads.message_files.entries) > 0 do %>
              <div class="mb-3 flex flex-wrap gap-2">
                <%= for entry <- @uploads.message_files.entries do %>
                  <div class="relative group">
                    <div class="flex items-center gap-2 bg-base-200 px-3 py-2 rounded-lg border border-base-300">
                      <%= cond do %>
                        <% String.starts_with?(entry.client_type, "image/") -> %>
                          <svg class="w-4 h-4 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                          </svg>
                        <% String.starts_with?(entry.client_type, "audio/") -> %>
                          <svg class="w-4 h-4 text-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
                          </svg>
                        <% true -> %>
                          <svg class="w-4 h-4 text-accent" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                          </svg>
                      <% end %>
                      <span class="text-sm truncate max-w-[150px]"><%= entry.client_name %></span>
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="text-error hover:text-error/80"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>

            <.form for={%{}} phx-submit="send_message" phx-change="validate_upload" class="flex gap-2">
              <label
                for="file-upload"
                class="cursor-pointer px-3 py-2 bg-base-200 hover:bg-base-300 text-base-content rounded-lg transition-colors flex items-center justify-center"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"
                  />
                </svg>
                <.live_file_input upload={@uploads.message_files} class="hidden" id="file-upload" />
              </label>

              <input
                type="text"
                name="message"
                value={@input}
                phx-change="update_input"
                disabled={@loading}
                placeholder="Type your message..."
                class="flex-1 px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent disabled:opacity-50"
              />
              <button
                type="submit"
                disabled={@loading || (@input == "" && length(@uploads.message_files.entries) == 0)}
                class="px-6 py-2 bg-primary text-primary-content rounded-lg hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                Send
              </button>
            </.form>
          </div>
        <% else %>
          <!-- Empty State -->
          <div class="flex-1 flex items-center justify-center p-6">
            <div class="text-center">
              <h2 class="text-2xl font-bold text-base-content mb-4">Welcome to ChatGPT Clone</h2>
              <p class="text-base-content/70 mb-6">
                Create a new conversation or select an existing one to get started
              </p>
              <button
                phx-click="new_conversation"
                class="px-6 py-3 bg-primary text-primary-content rounded-lg hover:bg-primary/90 font-medium transition-colors"
              >
                Start New Conversation
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
