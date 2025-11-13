defmodule ElixirBearWeb.SettingsLive do
  use ElixirBearWeb, :live_view

  alias ElixirBear.{Chat, Ollama, OpenAI}

  @impl true
  def mount(_params, _session, socket) do
    api_key = Chat.get_setting_value("openai_api_key") || ""
    system_prompt = Chat.get_setting_value("system_prompt") || ""
    llm_provider = Chat.get_setting_value("llm_provider") || "openai"
    openai_model = Chat.get_setting_value("openai_model") || "gpt-3.5-turbo"
    ollama_model = Chat.get_setting_value("ollama_model") || "codellama:latest"
    ollama_url = Chat.get_setting_value("ollama_url") || "http://localhost:11434"

    # Check Ollama connection status and fetch models
    {ollama_status, ollama_models} =
      case Ollama.check_connection(url: ollama_url) do
        {:ok, version} ->
          models =
            case Ollama.list_models(url: ollama_url) do
              {:ok, models} -> models
              {:error, _} -> []
            end

          {"Connected (version: #{version})", models}

        {:error, _} ->
          {"Not connected", []}
      end

    # Fetch OpenAI models if API key is present
    openai_models =
      if api_key != "" do
        case OpenAI.list_models(api_key) do
          {:ok, models} ->
            models
          {:error, _reason} ->
            OpenAI.default_models()
        end
      else
        OpenAI.default_models()
      end

    # Load background images
    background_images = Chat.list_background_images()
    selected_background = Chat.get_selected_background_image()

    socket =
      socket
      |> assign(:api_key, api_key)
      |> assign(:system_prompt, system_prompt)
      |> assign(:llm_provider, llm_provider)
      |> assign(:openai_model, openai_model)
      |> assign(:openai_models, openai_models)
      |> assign(:ollama_model, ollama_model)
      |> assign(:ollama_models, ollama_models)
      |> assign(:ollama_url, ollama_url)
      |> assign(:ollama_status, ollama_status)
      |> assign(:background_images, background_images)
      |> assign(:selected_background, selected_background)
      |> allow_upload(:background_image,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("update_api_key", %{"value" => api_key}, socket) do
    Chat.update_setting("openai_api_key", api_key)

    socket =
      socket
      |> assign(:api_key, api_key)
      |> put_flash(:info, "API key updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_system_prompt", %{"value" => system_prompt}, socket) do
    Chat.update_setting("system_prompt", system_prompt)

    socket =
      socket
      |> assign(:system_prompt, system_prompt)
      |> put_flash(:info, "System prompt updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_openai_model", %{"value" => openai_model}, socket) do
    Chat.update_setting("openai_model", openai_model)

    socket =
      socket
      |> assign(:openai_model, openai_model)
      |> put_flash(:info, "Model updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_ollama_model", %{"value" => ollama_model}, socket) do
    Chat.update_setting("ollama_model", ollama_model)

    socket =
      socket
      |> assign(:ollama_model, ollama_model)
      |> put_flash(:info, "Model updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_ollama_url", %{"value" => ollama_url}, socket) do
    Chat.update_setting("ollama_url", ollama_url)

    # Check Ollama connection status and fetch models
    {ollama_status, ollama_models} =
      case Ollama.check_connection(url: ollama_url) do
        {:ok, version} ->
          models =
            case Ollama.list_models(url: ollama_url) do
              {:ok, models} -> models
              {:error, _} -> []
            end

          {"Connected (version: #{version})", models}

        {:error, _} ->
          {"Not connected", []}
      end

    socket =
      socket
      |> assign(:ollama_url, ollama_url)
      |> assign(:ollama_status, ollama_status)
      |> assign(:ollama_models, ollama_models)
      |> put_flash(:info, "Ollama URL updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_provider", %{"llm_provider" => provider}, socket) do
    Chat.update_setting("llm_provider", provider)

    socket =
      socket
      |> assign(:llm_provider, provider)
      |> put_flash(:info, "Provider updated to #{provider}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_models", _params, socket) do
    llm_provider = socket.assigns.llm_provider

    socket =
      case llm_provider do
        "ollama" ->
          ollama_url = socket.assigns.ollama_url

          {ollama_status, ollama_models} =
            case Ollama.check_connection(url: ollama_url) do
              {:ok, version} ->
                models =
                  case Ollama.list_models(url: ollama_url) do
                    {:ok, models} -> models
                    {:error, _} -> []
                  end

                {"Connected (version: #{version})", models}

              {:error, _} ->
                {"Not connected", []}
            end

          socket
          |> assign(:ollama_status, ollama_status)
          |> assign(:ollama_models, ollama_models)
          |> put_flash(:info, "Refreshed Ollama models")

        "openai" ->
          api_key = socket.assigns.api_key

          openai_models =
            if api_key != "" do
              case OpenAI.list_models(api_key) do
                {:ok, models} -> models
                {:error, _} -> OpenAI.default_models()
              end
            else
              OpenAI.default_models()
            end

          socket
          |> assign(:openai_models, openai_models)
          |> put_flash(:info, "Refreshed OpenAI models")

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_background", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_background", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :background_image, fn %{path: path}, entry ->
        # Generate unique filename
        ext = Path.extname(entry.client_name)
        filename = "#{System.system_time(:second)}_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}#{ext}"
        dest = Path.join(["priv", "static", "uploads", "backgrounds", filename])

        # Copy file to destination
        File.cp!(path, dest)

        # Create database entry
        file_path = "/uploads/backgrounds/#{filename}"
        {:ok, background_image} = Chat.create_background_image(%{
          filename: filename,
          original_name: entry.client_name,
          file_path: file_path
        })

        {:ok, background_image}
      end)

    socket =
      if length(uploaded_files) > 0 do
        socket
        |> assign(:background_images, Chat.list_background_images())
        |> put_flash(:info, "Background image uploaded successfully")
      else
        socket
        |> put_flash(:error, "Failed to upload image")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_background", %{"id" => id}, socket) do
    case Chat.select_background_image(String.to_integer(id)) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:selected_background, Chat.get_selected_background_image())
          |> put_flash(:info, "Background image selected")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to select background")}
    end
  end

  @impl true
  def handle_event("delete_background", %{"id" => id}, socket) do
    background_image = Chat.get_background_image!(String.to_integer(id))

    # Delete file from filesystem
    file_path = Path.join(["priv", "static"] ++ String.split(background_image.file_path, "/", trim: true))
    File.rm(file_path)

    # Delete from database
    case Chat.delete_background_image(background_image) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:background_images, Chat.list_background_images())
          |> assign(:selected_background, Chat.get_selected_background_image())
          |> put_flash(:info, "Background image deleted")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete background")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-base-content">Settings</h1>
        <p class="mt-2 text-base-content/70">Configure your AI chat settings</p>
      </div>

      <div class="space-y-6">
        <!-- LLM Provider Selection -->
        <div>
          <label class="block text-sm font-medium text-base-content mb-3">
            LLM Provider
          </label>
          <div class="space-y-2">
            <label class="flex items-center gap-3 cursor-pointer">
              <input
                type="radio"
                name="llm_provider"
                value="openai"
                checked={@llm_provider == "openai"}
                phx-click="change_provider"
                phx-value-llm_provider="openai"
                class="w-4 h-4 text-primary"
              />
              <span class="text-base-content">OpenAI (GPT-3.5, GPT-4)</span>
            </label>
            <label class="flex items-center gap-3 cursor-pointer">
              <input
                type="radio"
                name="llm_provider"
                value="ollama"
                checked={@llm_provider == "ollama"}
                phx-click="change_provider"
                phx-value-llm_provider="ollama"
                class="w-4 h-4 text-primary"
              />
              <span class="text-base-content">Ollama (Local LLMs)</span>
            </label>
          </div>
        </div>
        <!-- OpenAI Settings -->
        <%= if @llm_provider == "openai" do %>
          <div class="border border-base-300 rounded-lg p-4 bg-base-100">
            <h3 class="text-lg font-medium text-base-content mb-4">OpenAI Configuration</h3>

            <div class="mb-4">
              <label for="api_key" class="block text-sm font-medium text-base-content mb-2">
                API Key
              </label>
              <input
                type="password"
                id="api_key"
                value={@api_key}
                phx-blur="update_api_key"
                class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                placeholder="sk-..."
              />
              <p class="mt-1 text-sm text-base-content/70">
                Your OpenAI API key. Get one at
                <a
                  href="https://platform.openai.com/api-keys"
                  target="_blank"
                  class="text-primary hover:text-primary/80"
                >
                  platform.openai.com
                </a>
              </p>
            </div>

            <div>
              <div class="flex items-center justify-between mb-2">
                <label for="openai_model" class="block text-sm font-medium text-base-content">
                  Model
                </label>
                <button
                  type="button"
                  phx-click="refresh_models"
                  class="text-xs text-primary hover:text-primary/80 flex items-center gap-1"
                >
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                  Refresh
                </button>
              </div>
              <select
                id="openai_model"
                name="value"
                phx-change="update_openai_model"
                class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
              >
                <%= for model <- @openai_models do %>
                  <option value={model} selected={model == @openai_model}><%= model %></option>
                <% end %>
              </select>
              <p class="mt-1 text-sm text-base-content/70">
                Select the OpenAI model to use for chat completions
              </p>
            </div>
          </div>
        <% end %>
        <!-- Ollama Settings -->
        <%= if @llm_provider == "ollama" do %>
          <div class="border border-base-300 rounded-lg p-4 bg-base-100">
            <h3 class="text-lg font-medium text-base-content mb-4">Ollama Configuration</h3>

            <div class="mb-4">
              <label for="ollama_url" class="block text-sm font-medium text-base-content mb-2">
                Ollama Server URL
              </label>
              <input
                type="text"
                id="ollama_url"
                value={@ollama_url}
                phx-blur="update_ollama_url"
                class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                placeholder="http://localhost:11434"
              />
              <p class="mt-1 text-sm text-base-content/70">
                Status: <span class={[
                  "font-medium",
                  String.contains?(@ollama_status, "Connected") && "text-success",
                  !String.contains?(@ollama_status, "Connected") && "text-error"
                ]}><%= @ollama_status %></span>
              </p>
            </div>

            <div>
              <div class="flex items-center justify-between mb-2">
                <label for="ollama_model" class="block text-sm font-medium text-base-content">
                  Model
                </label>
                <button
                  type="button"
                  phx-click="refresh_models"
                  class="text-xs text-primary hover:text-primary/80 flex items-center gap-1"
                >
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                  Refresh
                </button>
              </div>
              <%= if length(@ollama_models) > 0 do %>
                <select
                  id="ollama_model"
                  name="value"
                  phx-change="update_ollama_model"
                  class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                >
                  <%= for model <- @ollama_models do %>
                    <option value={model} selected={model == @ollama_model}><%= model %></option>
                  <% end %>
                </select>
                <p class="mt-1 text-sm text-base-content/70">
                  Select the Ollama model to use for chat completions
                </p>
              <% else %>
                <input
                  type="text"
                  id="ollama_model"
                  name="value"
                  value={@ollama_model}
                  phx-blur="update_ollama_model"
                  class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                  placeholder="codellama:latest"
                />
                <p class="mt-1 text-sm text-base-content/70">
                  No models found. Run <code class="bg-base-300 px-1 rounded">ollama pull MODEL_NAME</code>
                  to download models, then click Refresh.
                </p>
              <% end %>
            </div>
          </div>
        <% end %>
        <!-- System Prompt -->
        <div>
          <label for="system_prompt" class="block text-sm font-medium text-base-content mb-2">
            System Prompt
          </label>
          <textarea
            id="system_prompt"
            rows="6"
            phx-blur="update_system_prompt"
            class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
            placeholder="You are a helpful assistant..."
          ><%= @system_prompt %></textarea>
          <p class="mt-1 text-sm text-base-content/70">
            Optional system prompt for all conversations (can be overridden per conversation)
          </p>
        </div>

        <!-- Background Image Gallery -->
        <div class="border border-base-300 rounded-lg p-4 bg-base-100">
          <h3 class="text-lg font-medium text-base-content mb-4">Background Images</h3>

          <!-- Upload Section -->
          <div class="mb-6">
            <form phx-submit="upload_background" phx-change="validate_background">
              <div class="flex gap-4 items-end">
                <div class="flex-1">
                  <label class="block text-sm font-medium text-base-content mb-2">
                    Upload New Background
                  </label>
                  <.live_file_input upload={@uploads.background_image} class="file-input file-input-bordered w-full" />
                  <p class="mt-1 text-sm text-base-content/70">
                    Supported formats: JPG, PNG, GIF, WebP (Max 5MB)
                  </p>
                </div>
                <button
                  type="submit"
                  disabled={length(@uploads.background_image.entries) == 0}
                  class="btn btn-primary"
                >
                  <svg
                    class="w-5 h-5 mr-2"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    xmlns="http://www.w3.org/2000/svg"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"
                    >
                    </path>
                  </svg>
                  Upload
                </button>
              </div>
            </form>
          </div>

          <!-- Gallery Section -->
          <div>
            <h4 class="text-md font-medium text-base-content mb-3">Your Backgrounds</h4>
            <%= if length(@background_images) == 0 do %>
              <div class="text-center py-8 text-base-content/50">
                <svg
                  class="w-16 h-16 mx-auto mb-2 opacity-50"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  xmlns="http://www.w3.org/2000/svg"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                  >
                  </path>
                </svg>
                <p>No background images yet. Upload one to get started!</p>
              </div>
            <% else %>
              <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                <%= for bg_image <- @background_images do %>
                  <div class={"relative group rounded-lg overflow-hidden border-2 #{if @selected_background && @selected_background.id == bg_image.id, do: "border-primary shadow-lg", else: "border-base-300"}"}>
                    <img
                      src={bg_image.file_path}
                      alt={bg_image.original_name}
                      class="w-full h-32 object-cover"
                    />
                    <div class="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-50 transition-all flex items-center justify-center gap-2">
                      <button
                        phx-click="select_background"
                        phx-value-id={bg_image.id}
                        class="btn btn-sm btn-primary opacity-0 group-hover:opacity-100 transition-opacity"
                        title="Select as background"
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
                            d="M5 13l4 4L19 7"
                          >
                          </path>
                        </svg>
                      </button>
                      <button
                        phx-click="delete_background"
                        phx-value-id={bg_image.id}
                        data-confirm="Are you sure you want to delete this background image?"
                        class="btn btn-sm btn-error opacity-0 group-hover:opacity-100 transition-opacity"
                        title="Delete background"
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
                    <%= if @selected_background && @selected_background.id == bg_image.id do %>
                      <div class="absolute top-2 right-2 bg-primary text-primary-content text-xs px-2 py-1 rounded-full font-semibold">
                        Selected
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <div class="mt-8 pt-8 border-t border-base-300">
        <.link
          navigate={~p"/"}
          class="text-primary hover:text-primary/80 flex items-center gap-2"
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
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            >
            </path>
          </svg>
          Back to Chat
        </.link>
      </div>
    </div>
    """
  end
end
