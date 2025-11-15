defmodule ElixirBearWeb.ChatLive do
  use ElixirBearWeb, :live_view

  alias ElixirBear.{Chat, ConversationWorker, Ollama}
  alias ElixirBearWeb.Markdown

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
      |> assign(:processing_conversations, MapSet.new())
      |> assign(:solution_extraction_task, nil)
      |> assign(:extracting_solution, false)
      |> assign(:show_solution_modal, false)
      |> assign(:extracted_solution, nil)
      |> assign(:show_router_modal, false)
      |> assign(:matched_solution, nil)
      |> assign(:match_confidence, 0.0)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_llm_messages, nil)
      |> assign(:pending_saved_message_id, nil)
      |> allow_upload(:message_files,
        accept: ~w(.jpg .jpeg .png .gif .webp
                   .mp3 .mpga .m4a .wav
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
    # Unsubscribe from old conversation if exists
    if socket.assigns[:current_conversation] do
      Phoenix.PubSub.unsubscribe(ElixirBear.PubSub, "conversation:#{socket.assigns.current_conversation.id}")
    end

    conversation = Chat.get_conversation!(id)
    messages = Chat.list_messages_with_attachments(id)

    # Subscribe to PubSub for this conversation
    Phoenix.PubSub.subscribe(ElixirBear.PubSub, "conversation:#{id}")

    socket =
      socket
      |> assign(:current_conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:error, nil)
      |> assign(:processing_conversations, Map.get(socket.assigns, :processing_conversations, MapSet.new()))

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
  def handle_event("save_as_solution", %{"message-id" => message_id}, socket) do
    alias ElixirBear.Solutions.{Packager, LLMExtractor}

    message_id = String.to_integer(message_id)
    assistant_message = Chat.get_message!(message_id)

    # Find the user message (the one right before this assistant message)
    messages = socket.assigns.messages
    message_index = Enum.find_index(messages, fn m -> m.id == message_id end)

    user_message = if message_index && message_index > 0 do
      Enum.at(messages, message_index - 1)
    else
      nil
    end

    if user_message && user_message.role == "user" do
      # Package and extract in a background task
      task = Task.async(fn ->
        case Packager.validate_and_package(user_message.id, assistant_message.id) do
          {:ok, package} ->
            case LLMExtractor.extract_metadata(package) do
              {:ok, llm_metadata} ->
                complete_package = Packager.merge_llm_metadata(package, llm_metadata)
                {:ok, complete_package}

              {:error, reason} ->
                {:error, {:llm_extraction_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:packaging_failed, reason}}
        end
      end)

      socket =
        socket
        |> assign(:solution_extraction_task, task)
        |> assign(:extracting_solution, true)
        |> put_flash(:info, "Extracting solution metadata...")

      {:noreply, socket}
    else
      socket = put_flash(socket, :error, "Could not find the corresponding user message")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_solution_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_solution_modal, false)
      |> assign(:extracted_solution, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # This handler does nothing - it just prevents click events from bubbling up
    # Used to prevent modal from closing when clicking inside it
    {:noreply, socket}
  end

  @impl true
  def handle_event("close_router_modal", _params, socket) do
    # User dismissed the router modal without choosing
    # Proceed with normal LLM inference
    conversation = socket.assigns.current_conversation
    llm_messages = socket.assigns.pending_llm_messages
    saved_message_id = socket.assigns.pending_saved_message_id

    socket =
      socket
      |> assign(:show_router_modal, false)
      |> assign(:matched_solution, nil)
      |> assign(:match_confidence, 0.0)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_llm_messages, nil)
      |> assign(:pending_saved_message_id, nil)

    start_llm_inference(socket, conversation, llm_messages, saved_message_id)
  end

  @impl true
  def handle_event("use_router_solution", _params, socket) do
    # User accepted the matched solution
    matched_solution = socket.assigns.matched_solution
    conversation = socket.assigns.current_conversation

    # Create assistant message with the solution content
    {:ok, saved_message} =
      Chat.create_message(%{
        conversation_id: conversation.id,
        role: "assistant",
        content: matched_solution.answer_content
      })

    # Update messages in socket
    messages =
      socket.assigns.messages
      |> Enum.reject(fn msg -> msg.role == "assistant" && msg.content == "" end)

    messages =
      messages ++
        [%{id: saved_message.id, role: "assistant", content: matched_solution.answer_content}]

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:loading, false)
      |> assign(:show_router_modal, false)
      |> assign(:matched_solution, nil)
      |> assign(:match_confidence, 0.0)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_llm_messages, nil)
      |> assign(:pending_saved_message_id, nil)
      |> put_flash(:info, "Used solution from Treasure Trove!")

    {:noreply, socket}
  end

  @impl true
  def handle_event("reject_router_solution", _params, socket) do
    # User rejected the matched solution, proceed with LLM
    conversation = socket.assigns.current_conversation
    llm_messages = socket.assigns.pending_llm_messages
    saved_message_id = socket.assigns.pending_saved_message_id

    socket =
      socket
      |> assign(:show_router_modal, false)
      |> assign(:matched_solution, nil)
      |> assign(:match_confidence, 0.0)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_llm_messages, nil)
      |> assign(:pending_saved_message_id, nil)

    start_llm_inference(socket, conversation, llm_messages, saved_message_id)
  end

  @impl true
  def handle_event("update_solution_title", %{"value" => title}, socket) do
    case socket.assigns.extracted_solution do
      %{solution_attrs: attrs} = solution ->
        updated_solution = put_in(solution.solution_attrs.title, title)
        {:noreply, assign(socket, :extracted_solution, updated_solution)}

      _ ->
        # Solution not ready yet, ignore the update
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_solution_description", %{"value" => description}, socket) do
    case socket.assigns.extracted_solution do
      %{solution_attrs: %{metadata: _}} = solution ->
        updated_solution =
          update_in(solution.solution_attrs.metadata, fn meta ->
            Map.put(meta, :description, description)
          end)

        {:noreply, assign(socket, :extracted_solution, updated_solution)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_solution_difficulty", %{"value" => difficulty}, socket) do
    case socket.assigns.extracted_solution do
      %{solution_attrs: %{metadata: _}, tags_attrs: _} = solution ->
        updated_solution =
          update_in(solution.solution_attrs.metadata, fn meta ->
            Map.put(meta, :difficulty, difficulty)
          end)

        # Also update tags
        updated_solution =
          update_in(updated_solution.tags_attrs, fn tags ->
            tags
            |> Enum.reject(fn tag -> tag.tag_type == "difficulty" end)
            |> then(& &1 ++ [%{tag_type: "difficulty", tag_value: difficulty}])
          end)

        {:noreply, assign(socket, :extracted_solution, updated_solution)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_topic", %{"key" => "Enter", "value" => topic}, socket) when topic != "" do
    topic = String.trim(topic) |> String.downcase()

    case socket.assigns.extracted_solution do
      %{solution_attrs: %{metadata: %{topics: _}}, tags_attrs: _} = solution when topic != "" ->
        updated_solution =
          solution
          |> update_in([:solution_attrs, :metadata, :topics], fn topics ->
            if topic in topics do
              topics
            else
              topics ++ [topic]
            end
          end)
          |> update_in([:tags_attrs], fn tags ->
            if Enum.any?(tags, fn tag -> tag.tag_type == "topic" && tag.tag_value == topic end) do
              tags
            else
              tags ++ [%{tag_type: "topic", tag_value: topic}]
            end
          end)

        {:noreply, assign(socket, :extracted_solution, updated_solution)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("add_topic", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("remove_topic", %{"topic" => topic}, socket) do
    case socket.assigns.extracted_solution do
      %{solution_attrs: %{metadata: %{topics: _}}, tags_attrs: _} = solution ->
        updated_solution =
          solution
          |> update_in([:solution_attrs, :metadata, :topics], fn topics ->
            List.delete(topics, topic)
          end)
          |> update_in([:tags_attrs], fn tags ->
            Enum.reject(tags, fn tag -> tag.tag_type == "topic" && tag.tag_value == topic end)
          end)

        {:noreply, assign(socket, :extracted_solution, updated_solution)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_solution", _params, socket) do
    alias ElixirBear.Solutions

    solution = socket.assigns.extracted_solution

    case Solutions.create_solution_with_associations(
           solution.solution_attrs,
           solution.code_blocks_attrs,
           solution.tags_attrs
         ) do
      {:ok, saved_solution} ->
        socket =
          socket
          |> assign(:show_solution_modal, false)
          |> assign(:extracted_solution, nil)
          |> put_flash(:info, "Solution saved to Treasure Trove! ID: #{saved_solution.id}")

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to save solution: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event("update_code_block", %{"message_id" => message_id, "new_content" => new_content}, socket) do
    # Get the message from the database
    message = Chat.get_message!(message_id)

    # For simplicity, if the message is just a code block (starts with ```), replace entirely
    # Otherwise, try to find and replace the first code block
    updated_content =
      if String.starts_with?(String.trim(message.content), "```") do
        new_content
      else
        replace_first_code_block(message.content, new_content)
      end

    case Chat.update_message(message, %{content: updated_content}) do
      {:ok, _updated_message} ->
        # Reload messages to show the updated content
        messages = Chat.list_messages_with_attachments(socket.assigns.current_conversation.id)
        {:noreply, assign(socket, :messages, messages)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update code block")}
    end
  end

  @impl true
  def handle_info({ConversationWorker, {:streaming_started, _user_message_id}}, socket) do
    # Worker started streaming - already handled in send_message
    {:noreply, socket}
  end

  @impl true
  def handle_info({ConversationWorker, {:content_update, content}}, socket) do
    # Update the last message (assistant's response) with new content
    messages = socket.assigns.messages

    updated_messages =
      case List.last(messages) do
        %{role: "assistant"} ->
          # Update the temp assistant message with new content
          List.update_at(messages, -1, fn _msg ->
            %{role: "assistant", content: content}
          end)

        _ ->
          # No temp message, add one
          messages ++ [%{role: "assistant", content: content}]
      end

    {:noreply, assign(socket, :messages, updated_messages)}
  end

  @impl true
  def handle_info({ConversationWorker, {:streaming_complete, saved_message}}, socket) do
    conversation = socket.assigns.current_conversation

    # Replace temp message with saved message
    messages =
      socket.assigns.messages
      |> Enum.reject(fn msg -> msg.role == "assistant" && !Map.has_key?(msg, :id) end)
      |> Kernel.++([saved_message])

    # Remove conversation from processing set
    processing_conversations =
      socket.assigns.processing_conversations
      |> MapSet.delete(conversation.id)

    # Update conversation title if it's the first exchange
    socket =
      if length(messages) == 2 do
        title = Chat.generate_conversation_title(conversation.id)
        {:ok, updated_conversation} = Chat.update_conversation(conversation, %{title: title})
        conversations = Chat.list_conversations()

        socket
        |> assign(:current_conversation, updated_conversation)
        |> assign(:conversations, conversations)
      else
        socket
      end

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:loading, false)
      |> assign(:processing_conversations, processing_conversations)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ConversationWorker, {:streaming_error, error_message}}, socket) do
    conversation = socket.assigns.current_conversation

    # Remove the temporary assistant message
    messages =
      socket.assigns.messages
      |> Enum.reject(fn msg -> msg.role == "assistant" && !Map.has_key?(msg, :id) end)

    # Remove conversation from processing set
    processing_conversations =
      socket.assigns.processing_conversations
      |> MapSet.delete(conversation.id)

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:loading, false)
      |> assign(:processing_conversations, processing_conversations)
      |> assign(:error, error_message)

    {:noreply, socket}
  end

  # Handle solution extraction task completion
  def handle_info({ref, result}, socket) do
    # Check if this is our solution extraction task
    if socket.assigns[:solution_extraction_task] && socket.assigns.solution_extraction_task.ref == ref do
      Process.demonitor(ref, [:flush])

      case result do
        {:ok, complete_package} ->
          socket =
            socket
            |> assign(:extracted_solution, complete_package)
            |> assign(:extracting_solution, false)
            |> assign(:show_solution_modal, true)
            |> assign(:solution_extraction_task, nil)
            |> put_flash(:info, "Solution extracted! Review and save below.")

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:extracting_solution, false)
            |> assign(:solution_extraction_task, nil)
            |> put_flash(:error, "Failed to extract solution: #{inspect(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    # Task monitor down message
    {:noreply, socket}
  end

  defp send_message(socket, user_message) do
    require Logger
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
        # Process uploaded files
        uploaded_files =
          consume_uploaded_entries(socket, :message_files, fn %{path: path}, entry ->
            {:ok, process_uploaded_file(path, entry)}
          end)

        # Read text file contents and append to message
        text_content =
          uploaded_files
          |> Enum.filter(fn {file_type, _, _, _, _} -> file_type == "text" end)
          |> Enum.map(fn {_, file_path, original_name, _, _} ->
            content = File.read!(Path.join(["priv", "static"] ++ String.split(file_path, "/", trim: true)))
            "\n\n--- File: #{original_name} ---\n#{content}\n--- End of #{original_name} ---"
          end)
          |> Enum.join("\n")

        # Combine user message with text file contents
        full_message = if text_content != "", do: user_message <> text_content, else: user_message

        # Save user message
        {:ok, saved_message} =
          Chat.create_message(%{
            conversation_id: conversation.id,
            role: "user",
            content: full_message
          })

        # Save file attachments and collect them
        attachments =
          Enum.map(uploaded_files, fn {file_type, file_path, original_name, mime_type, file_size} ->
            {:ok, attachment} =
              Chat.create_message_attachment(%{
                message_id: saved_message.id,
                file_type: file_type,
                file_path: file_path,
                original_name: original_name,
                mime_type: mime_type,
                file_size: file_size
              })

            attachment
          end)

        # Add user message to display with attachments
        user_message_map = %{
          id: saved_message.id,
          role: "user",
          content: full_message,
          attachments: attachments
        }

        messages = socket.assigns.messages ++ [user_message_map]

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

        # Prepare messages with multimodal content support for Vision API
        llm_messages =
          filtered_messages
          |> Enum.map(fn msg ->
            content = prepare_message_content(msg)
            %{role: msg.role, content: content}
          end)

        llm_messages =
          if system_prompt && system_prompt != "" do
            [%{role: "system", content: system_prompt}] ++ llm_messages
          else
            llm_messages
          end

        # Check router for matching solutions first
        alias ElixirBear.Solutions.Router

        case Router.find_matching_solution(user_message) do
          {:ok, matched_solution, confidence} ->
            # Found a matching solution! Show recommendation modal
            Logger.info("Router: Found matching solution (ID: #{matched_solution.id}, confidence: #{confidence})")

            socket =
              socket
              |> assign(:show_router_modal, true)
              |> assign(:matched_solution, matched_solution)
              |> assign(:match_confidence, confidence)
              |> assign(:pending_user_message, user_message)
              |> assign(:pending_llm_messages, llm_messages)
              |> assign(:pending_saved_message_id, saved_message.id)

            {:noreply, socket}

          _ ->
            # No match or router disabled, proceed with normal LLM inference
            Logger.info("Router: No match found, proceeding with LLM")
            start_llm_inference(socket, conversation, llm_messages, saved_message.id)
        end
    end
  end

  defp start_llm_inference(socket, conversation, llm_messages, saved_message_id) do
    # Start conversation worker for background inference
    require Logger
    Logger.info("Attempting to start worker for conversation #{conversation.id}")

    case ConversationWorker.start_inference(
           conversation.id,
           llm_messages,
           saved_message_id
         ) do
          {:ok, _pid} ->
            # Worker started successfully
            Logger.info("Worker started successfully for conversation #{conversation.id}")

            # Track this conversation as processing
            processing_conversations =
              socket.assigns.processing_conversations
              |> MapSet.put(conversation.id)

            socket = assign(socket, :processing_conversations, processing_conversations)

            {:noreply, socket}

          {:error, :already_running} ->
            # A worker is already processing this conversation
            Logger.warning("Worker already running for conversation #{conversation.id}")

            {:noreply,
             put_flash(socket, :info, "A response is already being generated for this conversation")}

          {:error, reason} ->
            # Failed to start worker
            Logger.error("Failed to start worker: #{inspect(reason)}")

            {:noreply, put_flash(socket, :error, "Failed to start inference: #{inspect(reason)}")}
        end
  end

  defp prepare_message_content(message) do
    # Check if message has image attachments
    has_images =
      Map.has_key?(message, :attachments) &&
        Enum.any?(message.attachments, fn att -> att.file_type == "image" end)

    # If there are images, use multimodal content format
    if has_images do
      image_attachments =
        message.attachments
        |> Enum.filter(fn att -> att.file_type == "image" end)

      # Build content array with text and images
      text_content = [%{type: "text", text: message.content}]

      image_content =
        Enum.map(image_attachments, fn att ->
          # Read image file and encode as base64
          file_path = Path.join(["priv", "static"] ++ String.split(att.file_path, "/", trim: true))
          image_data = File.read!(file_path)
          base64_image = Base.encode64(image_data)

          # Determine image format from mime type
          image_format =
            case att.mime_type do
              "image/jpeg" -> "jpeg"
              "image/jpg" -> "jpeg"
              "image/png" -> "png"
              "image/gif" -> "gif"
              "image/webp" -> "webp"
              _ -> "jpeg"
            end

          %{
            type: "image_url",
            image_url: %{
              url: "data:image/#{image_format};base64,#{base64_image}"
            }
          }
        end)

      text_content ++ image_content
    else
      # For other providers or no images, just return text content
      message.content
    end
  end

  defp process_uploaded_file(path, entry) do
    # Determine file type based on MIME type
    file_type =
      cond do
        String.starts_with?(entry.client_type, "image/") -> "image"
        String.starts_with?(entry.client_type, "audio/") -> "audio"
        true -> "text"
      end

    # Generate unique filename
    ext = Path.extname(entry.client_name)
    filename = "#{System.system_time(:second)}_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}#{ext}"

    # Determine subdirectory based on file type
    subdir = case file_type do
      "image" -> "images"
      "audio" -> "audio"
      "text" -> "text"
    end

    dest = Path.join(["priv", "static", "uploads", "attachments", subdir, filename])

    # Ensure directory exists
    dest |> Path.dirname() |> File.mkdir_p!()

    # Copy file to destination
    File.cp!(path, dest)

    # Ensure file is synced to disk
    {:ok, fd} = :file.open(dest, [:read, :raw])
    :ok = :file.sync(fd)
    :ok = :file.close(fd)

    # Get file size
    %{size: file_size} = File.stat!(dest)

    # Create file path for database
    file_path = "/uploads/attachments/#{subdir}/#{filename}"

    {file_type, file_path, entry.client_name, entry.client_type, file_size}
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
                <div class="flex items-center gap-2">
                  <span class="text-sm truncate block flex-1">{conversation.title}</span>
                  <%= if MapSet.member?(@processing_conversations, conversation.id) do %>
                    <svg
                      class="animate-spin h-4 w-4 text-primary"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        class="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        stroke-width="4"
                      >
                      </circle>
                      <path
                        class="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                      >
                      </path>
                    </svg>
                  <% end %>
                </div>
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
            navigate={~p"/solutions"}
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
                d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
              >
              </path>
            </svg>
            Treasure Trove
          </.link>

          <.link
            navigate={~p"/settings"}
            class="flex items-center gap-2 px-4 py-2 hover:bg-base-100 rounded-lg transition-colors mt-2"
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
            phx-hook="CodeBlock"
            id="messages-container"
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

                  <!-- Show attachments if present -->
                  <%= if Map.has_key?(message, :attachments) && is_list(message.attachments) && length(message.attachments) > 0 do %>
                    <div class="mb-2 flex flex-wrap gap-2">
                      <%= for attachment <- message.attachments do %>
                        <%= cond do %>
                          <% attachment.file_type == "image" -> %>
                            <div class="relative group">
                              <img
                                src={"#{attachment.file_path}?v=#{attachment.id}"}
                                alt={attachment.original_name}
                                class="max-w-xs max-h-64 rounded-lg border border-base-300"
                                loading="lazy"
                              />
                              <div class="absolute bottom-0 left-0 right-0 bg-black/70 text-white text-xs px-2 py-1 opacity-0 group-hover:opacity-100 transition-opacity rounded-b-lg">
                                {attachment.original_name}
                              </div>
                            </div>
                          <% attachment.file_type == "audio" -> %>
                            <div class="w-full max-w-md">
                              <div class="text-xs mb-1 opacity-70">{attachment.original_name}</div>
                              <audio controls class="w-full">
                                <source src={attachment.file_path} type={attachment.mime_type} />
                                Your browser does not support the audio element.
                              </audio>
                            </div>
                          <% attachment.file_type == "text" -> %>
                            <div class="flex items-center gap-2 bg-base-300 px-3 py-2 rounded-lg text-sm">
                              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                              </svg>
                              <a
                                href={attachment.file_path}
                                target="_blank"
                                class="hover:underline"
                              >
                                {attachment.original_name}
                              </a>
                            </div>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>

                  <div class="prose prose-sm max-w-none message-content">
                    {Markdown.to_html(message.content, message_id: Map.get(message, :id))}
                  </div>

                  <!-- Save as Solution Button (only for assistant messages with code) -->
                  <%= if message.role == "assistant" && String.contains?(message.content, "```") do %>
                    <div class="mt-3 pt-3 border-t border-base-300">
                      <button
                        phx-click="save_as_solution"
                        phx-value-message-id={message.id}
                        class="btn btn-sm btn-outline btn-primary gap-2"
                        title="Save this solution to Treasure Trove"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
                        </svg>
                        Save to Treasure Trove
                      </button>
                    </div>
                  <% end %>
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

            <.form
              for={%{}}
              phx-submit="send_message"
              phx-change="validate_upload"
              phx-drop-target={@uploads.message_files.ref}
              phx-hook="PasteUpload"
              id="message-form"
              class="flex gap-2"
            >
              <label
                class="cursor-pointer px-3 py-2 bg-base-200 hover:bg-base-300 text-base-content rounded-lg transition-colors flex items-center justify-center"
              >
                <.live_file_input upload={@uploads.message_files} class="hidden" />
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"
                  />
                </svg>
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

    <!-- Solution Review Modal -->
    <%= if @show_solution_modal && @extracted_solution do %>
      <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" phx-click="close_solution_modal">
        <div class="bg-base-100 rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-y-auto" phx-click="stop_propagation">
          <div class="sticky top-0 bg-base-100 border-b border-base-300 px-6 py-4 flex items-center justify-between">
            <h2 class="text-2xl font-bold text-base-content flex items-center gap-2">
              <svg class="w-6 h-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
              </svg>
              Review Solution
            </h2>
            <button phx-click="close_solution_modal" class="btn btn-sm btn-circle btn-ghost">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <div class="p-6 space-y-6" phx-click="stop_propagation">
            <!-- Title -->
            <div>
              <label class="block text-sm font-medium text-base-content mb-2">Title</label>
              <input
                type="text"
                value={@extracted_solution.solution_attrs.title}
                phx-blur="update_solution_title"
                class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                placeholder="Enter a descriptive title..."
              />
            </div>

            <!-- Description -->
            <div>
              <label class="block text-sm font-medium text-base-content mb-2">Description</label>
              <textarea
                rows="3"
                phx-blur="update_solution_description"
                class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                placeholder="Brief description of what this solution teaches..."
              ><%= Map.get(@extracted_solution.solution_attrs.metadata, :description, "") %></textarea>
            </div>

            <!-- Topics -->
            <div>
              <label class="block text-sm font-medium text-base-content mb-2">Topics</label>
              <div class="flex flex-wrap gap-2 mb-2">
                <%= for topic <- Map.get(@extracted_solution.solution_attrs.metadata, :topics, []) do %>
                  <span class="badge badge-primary gap-2">
                    <%= topic %>
                    <button phx-click="remove_topic" phx-value-topic={topic} class="hover:text-error">
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </span>
                <% end %>
              </div>
              <div class="flex gap-2">
                <input
                  type="text"
                  id="new-topic-input"
                  phx-key="Enter"
                  phx-keydown="add_topic"
                  class="flex-1 px-3 py-2 text-sm bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                  placeholder="Add a topic and press Enter..."
                />
              </div>
            </div>

            <!-- Difficulty -->
            <div>
              <label class="block text-sm font-medium text-base-content mb-2">Difficulty</label>
              <select
                phx-change="update_solution_difficulty"
                class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
              >
                <%= for diff <- ["beginner", "intermediate", "advanced"] do %>
                  <option value={diff} selected={diff == Map.get(@extracted_solution.solution_attrs.metadata, :difficulty)}><%= String.capitalize(diff) %></option>
                <% end %>
              </select>
            </div>

            <!-- Code Blocks Preview -->
            <div>
              <label class="block text-sm font-medium text-base-content mb-2">
                Code Blocks (<%= length(@extracted_solution.code_blocks_attrs) %>)
              </label>
              <div class="space-y-3">
                <%= for {block, idx} <- Enum.with_index(@extracted_solution.code_blocks_attrs) do %>
                  <div class="bg-base-200 rounded-lg p-4 border border-base-300">
                    <div class="flex items-center justify-between mb-2">
                      <span class="text-xs font-medium text-base-content/70">
                        Block <%= idx + 1 %> <%= if block.language, do: "• #{block.language}", else: "" %>
                      </span>
                    </div>
                    <pre class="text-xs bg-base-300 p-3 rounded overflow-x-auto"><code><%= block.code %></code></pre>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Action Buttons -->
            <div class="flex gap-3 pt-4 border-t border-base-300">
              <button
                phx-click="save_solution"
                class="btn btn-primary flex-1"
              >
                <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                Save to Treasure Trove
              </button>
              <button
                phx-click="close_solution_modal"
                class="btn btn-ghost"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>

    <!-- Router Recommendation Modal -->
    <%= if @show_router_modal && @matched_solution do %>
      <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
        <div class="bg-base-100 rounded-lg shadow-2xl max-w-3xl w-full max-h-[85vh] overflow-hidden flex flex-col">
          <!-- Header -->
          <div class="bg-primary px-6 py-4 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <svg class="w-8 h-8 text-primary-content" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                >
                </path>
              </svg>
              <div>
                <h2 class="text-xl font-bold text-primary-content">Solution Found in Treasure Trove!</h2>
                <p class="text-sm text-primary-content/80">
                  Match confidence: <%= Float.round(@match_confidence * 100, 1) %>%
                </p>
              </div>
            </div>
            <button phx-click="close_router_modal" class="btn btn-sm btn-circle btn-ghost text-primary-content">
              ✕
            </button>
          </div>

          <!-- Content -->
          <div class="flex-1 overflow-y-auto px-6 py-6">
            <div class="alert alert-info mb-6">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="stroke-current shrink-0 w-6 h-6"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                >
                </path>
              </svg>
              <div>
                <h3 class="font-bold">I found a similar solution you saved before!</h3>
                <p class="text-sm">
                  You can use this existing solution or ask me to generate a fresh response.
                </p>
              </div>
            </div>

            <!-- Solution Details -->
            <div class="space-y-4">
              <div>
                <h3 class="text-lg font-bold text-base-content mb-2">
                  <%= @matched_solution.title || "Saved Solution" %>
                </h3>

                <!-- Tags -->
                <div class="flex flex-wrap gap-2 mb-4">
                  <%= for tag <- Enum.filter(@matched_solution.tags, fn t -> t.tag_type == "topic" end) do %>
                    <span class="badge badge-primary"><%= tag.tag_value %></span>
                  <% end %>

                  <%= for tag <- Enum.filter(@matched_solution.tags, fn t -> t.tag_type == "difficulty" end) do %>
                    <span class={
                      "badge " <>
                        case tag.tag_value do
                          "beginner" -> "badge-success"
                          "intermediate" -> "badge-warning"
                          "advanced" -> "badge-error"
                          _ -> "badge-neutral"
                        end
                    }>
                      <%= tag.tag_value %>
                    </span>
                  <% end %>
                </div>

                <%= if get_in(@matched_solution.metadata, ["description"]) do %>
                  <p class="text-base-content/70 mb-4">
                    <%= get_in(@matched_solution.metadata, ["description"]) %>
                  </p>
                <% end %>
              </div>

              <!-- Original Question -->
              <div>
                <h4 class="font-semibold text-base-content mb-2">Original Question:</h4>
                <div class="bg-base-200 rounded-lg p-3 text-sm">
                  <%= @matched_solution.user_query %>
                </div>
              </div>

              <!-- Preview of Answer -->
              <div>
                <h4 class="font-semibold text-base-content mb-2">
                  Answer Preview (<%= length(@matched_solution.code_blocks) %> code block(s)):
                </h4>
                <div class="bg-base-200 rounded-lg p-3 text-sm max-h-48 overflow-y-auto">
                  <%= String.slice(@matched_solution.answer_content, 0..300) %><%= if String.length(@matched_solution.answer_content) > 300,
                    do: "...",
                    else: "" %>
                </div>
              </div>
            </div>
          </div>

          <!-- Actions -->
          <div class="border-t border-base-300 px-6 py-4 flex gap-3 justify-end">
            <button phx-click="reject_router_solution" class="btn btn-ghost gap-2">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                >
                </path>
              </svg>
              Ask LLM Instead
            </button>
            <button phx-click="use_router_solution" class="btn btn-primary gap-2">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M5 13l4 4L19 7"
                >
                </path>
              </svg>
              Use This Solution
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Private helper to replace the first code block in markdown
  defp replace_first_code_block(markdown, new_code) do
    # Match the first code block (```language\n...code...\n```)
    regex = ~r/```\w*\n.*?```/s

    case Regex.run(regex, markdown, return: :index) do
      [{start_pos, length}] ->
        # Extract the language identifier from the original code block
        original_block = String.slice(markdown, start_pos, length)
        lang = extract_language(original_block)

        # Create new code block with the same language
        new_block = "```#{lang}\n#{new_code}\n```"

        # Replace the code block
        before = String.slice(markdown, 0, start_pos)
        after_pos = start_pos + length
        after_text = String.slice(markdown, after_pos..-1//1)

        before <> new_block <> after_text

      nil ->
        # No code block found, return original
        markdown
    end
  end

  defp extract_language(code_block) do
    case Regex.run(~r/```(\w*)/, code_block) do
      [_, lang] -> lang
      _ -> ""
    end
  end
end
