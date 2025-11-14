defmodule ElixirBearWeb.ChatLive do
  use ElixirBearWeb, :live_view

  alias ElixirBear.{Chat, Ollama, OpenAI}
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
    conversation = Chat.get_conversation!(id)
    messages = Chat.list_messages_with_attachments(id)

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

        # Check if any message has images
        has_images =
          filtered_messages
          |> Enum.any?(fn msg ->
            Map.has_key?(msg, :attachments) &&
              Enum.any?(msg.attachments, fn att -> att.file_type == "image" end)
          end)

        # Start async task to call LLM with streaming
        parent = self()

        Task.start(fn ->
          callback = fn chunk ->
            send(parent, {:stream_content, chunk})
          end

          result =
            # If there are images, always use OpenAI Vision API regardless of provider
            if has_images do
              api_key = Chat.get_setting_value("openai_api_key")
              vision_model = Chat.get_setting_value("vision_model") || "gpt-4o"
              OpenAI.stream_chat_completion(api_key, llm_messages, callback, model: vision_model)
            else
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
                  <%= if Map.has_key?(message, :attachments) && length(message.attachments) > 0 do %>
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
