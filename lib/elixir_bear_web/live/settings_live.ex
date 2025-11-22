defmodule ElixirBearWeb.SettingsLive do
  use ElixirBearWeb, :live_view

  alias ElixirBear.{Chat, Ollama, OpenAI}

  @impl true
  def mount(_params, _session, socket) do
    settings = ElixirBear.SettingsCache.get_all_settings()

    api_key = settings.api_key
    system_prompt = settings.system_prompt
    llm_provider = settings.llm_provider
    openai_model = settings.openai_model
    vision_model = settings.vision_model
    ollama_model = settings.ollama_model
    ollama_url = settings.ollama_url

    solution_extraction_provider = settings.solution_extraction_provider
    solution_extraction_ollama_model = settings.solution_extraction_ollama_model
    solution_extraction_openai_model = settings.solution_extraction_openai_model

    enable_solution_router = settings.enable_solution_router
    solution_router_threshold = settings.solution_router_threshold

    enable_prompt_orchestrator = settings.enable_prompt_orchestrator
    orchestrator_prompts_json = settings.orchestrator_prompts_json

    enable_copy_blocker = settings.enable_copy_blocker

    {:ok, {ollama_status, ollama_models}} =
      ElixirBear.SettingsCache.get_ollama_models(ollama_url)

    openai_models = ElixirBear.SettingsCache.get_openai_models(api_key)

    background_images = Chat.list_background_images()
    selected_background = Chat.get_selected_background_image()

    socket =
      socket
      |> assign(:api_key, api_key)
      |> assign(:system_prompt, system_prompt)
      |> assign(:llm_provider, llm_provider)
      |> assign(:openai_model, openai_model)
      |> assign(:openai_models, openai_models)
      |> assign(:vision_model, vision_model)
      |> assign(:ollama_model, ollama_model)
      |> assign(:ollama_models, ollama_models)
      |> assign(:ollama_url, ollama_url)
      |> assign(:ollama_status, ollama_status)
      |> assign(:solution_extraction_provider, solution_extraction_provider)
      |> assign(:solution_extraction_ollama_model, solution_extraction_ollama_model)
      |> assign(:solution_extraction_openai_model, solution_extraction_openai_model)
      |> assign(:enable_solution_router, enable_solution_router)
      |> assign(:solution_router_threshold, solution_router_threshold)
      |> assign(:enable_prompt_orchestrator, enable_prompt_orchestrator)
      |> assign(:orchestrator_prompts_json, orchestrator_prompts_json)
      |> assign(:orchestrator_json_error, nil)
      |> assign(:enable_copy_blocker, enable_copy_blocker)
      |> assign(:background_images, background_images)
      |> assign(:selected_background, selected_background)
      |> assign(:pending_previews, %{})
      |> allow_upload(:background_image,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event(
        "background_preview",
        %{"client_name" => client_name, "preview_url" => preview_url},
        socket
      ) do
    pending = Map.put(socket.assigns[:pending_previews] || %{}, client_name, preview_url)

    {:noreply, assign(socket, :pending_previews, pending)}
  end

  @impl true
  def handle_event("update_api_key", %{"value" => api_key}, socket) do
    Chat.update_setting("openai_api_key", api_key)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:api_key, api_key)
      |> put_flash(:info, "API key updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_system_prompt", %{"value" => system_prompt}, socket) do
    Chat.update_setting("system_prompt", system_prompt)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:system_prompt, system_prompt)
      |> put_flash(:info, "System prompt updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_openai_model", %{"value" => openai_model}, socket) do
    Chat.update_setting("openai_model", openai_model)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:openai_model, openai_model)
      |> put_flash(:info, "Model updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_vision_model", %{"value" => vision_model}, socket) do
    Chat.update_setting("vision_model", vision_model)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:vision_model, vision_model)
      |> put_flash(:info, "Vision model updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_ollama_model", params, socket) do
    IO.inspect(params, label: "update_ollama_model params")
    ollama_model = params["value"] || params["ollama_model"] || socket.assigns.ollama_model
    IO.inspect(ollama_model, label: "ollama_model to save")

    case Chat.update_setting("ollama_model", ollama_model) do
      {:ok, _setting} ->
        ElixirBear.SettingsCache.invalidate()

        socket =
          socket
          |> assign(:ollama_model, ollama_model)
          |> put_flash(:info, "Model updated to #{ollama_model}")

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> put_flash(:error, "Failed to update model: #{inspect(changeset.errors)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_ollama_url", %{"value" => ollama_url}, socket) do
    Chat.update_setting("ollama_url", ollama_url)
    ElixirBear.SettingsCache.invalidate()

    {:ok, {ollama_status, ollama_models}} =
      ElixirBear.SettingsCache.get_ollama_models(ollama_url)

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
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:llm_provider, provider)
      |> put_flash(:info, "Provider updated to #{provider}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_models", _params, socket) do
    llm_provider = socket.assigns.llm_provider
    ElixirBear.SettingsCache.invalidate()

    socket =
      case llm_provider do
        "ollama" ->
          ollama_url = socket.assigns.ollama_url

          {:ok, {ollama_status, ollama_models}} =
            ElixirBear.SettingsCache.get_ollama_models(ollama_url)

          socket
          |> assign(:ollama_status, ollama_status)
          |> assign(:ollama_models, ollama_models)
          |> put_flash(:info, "Refreshed Ollama models")

        "openai" ->
          api_key = socket.assigns.api_key

          openai_models = ElixirBear.SettingsCache.get_openai_models(api_key)

          socket
          |> assign(:openai_models, openai_models)
          |> put_flash(:info, "Refreshed OpenAI models")

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_solution_extraction_provider", %{"provider" => provider}, socket) do
    Chat.update_setting("solution_extraction_provider", provider)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:solution_extraction_provider, provider)
      |> put_flash(:info, "Solution extraction provider updated to #{provider}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_solution_extraction_ollama_model", %{"value" => model}, socket) do
    Chat.update_setting("solution_extraction_ollama_model", model)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:solution_extraction_ollama_model, model)
      |> put_flash(:info, "Solution extraction model updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_solution_extraction_openai_model", %{"value" => model}, socket) do
    Chat.update_setting("solution_extraction_openai_model", model)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:solution_extraction_openai_model, model)
      |> put_flash(:info, "Solution extraction model updated")

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_solution_router", _params, socket) do
    current_value = socket.assigns.enable_solution_router
    new_value = if current_value == "true", do: "false", else: "true"

    Chat.update_setting("enable_solution_router", new_value)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:enable_solution_router, new_value)
      |> put_flash(
        :info,
        "Solution router #{if new_value == "true", do: "enabled", else: "disabled"}"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_solution_router_threshold", %{"value" => threshold}, socket) do
    threshold_float = String.to_float(threshold)

    threshold_clamped =
      threshold_float
      |> max(0.0)
      |> min(1.0)
      |> Float.to_string()

    Chat.update_setting("solution_router_threshold", threshold_clamped)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:solution_router_threshold, threshold_clamped)
      |> put_flash(:info, "Solution router threshold updated to #{threshold_clamped}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_orchestrator", _params, socket) do
    current_value = socket.assigns.enable_prompt_orchestrator
    new_value = if current_value == "true", do: "false", else: "true"

    Chat.update_setting("enable_prompt_orchestrator", new_value)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:enable_prompt_orchestrator, new_value)
      |> put_flash(
        :info,
        "Prompt orchestrator #{if new_value == "true", do: "enabled", else: "disabled"}"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_copy_blocker", _params, socket) do
    current_value = socket.assigns.enable_copy_blocker
    new_value = if current_value == "true", do: "false", else: "true"

    Chat.update_setting("enable_copy_blocker", new_value)
    ElixirBear.SettingsCache.invalidate()

    socket =
      socket
      |> assign(:enable_copy_blocker, new_value)
      |> put_flash(
        :info,
        "Copy blocker #{if new_value == "true", do: "enabled", else: "disabled"}"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_orchestrator_prompts", %{"value" => json_string}, socket) do
    case Jason.decode(json_string) do
      {:ok, prompts} when is_map(prompts) ->
        Chat.update_setting("orchestrator_prompts", json_string)
        ElixirBear.SettingsCache.invalidate()

        categories = Chat.list_orchestrator_categories()

        socket =
          socket
          |> assign(:orchestrator_prompts_json, json_string)
          |> assign(:orchestrator_json_error, nil)
          |> put_flash(:info, "System prompts updated (#{length(categories)} categories)")

        {:noreply, socket}

      {:error, %Jason.DecodeError{} = error} ->
        socket =
          socket
          |> assign(:orchestrator_prompts_json, json_string)
          |> assign(:orchestrator_json_error, "Invalid JSON: #{Exception.message(error)}")
          |> put_flash(
            :error,
            "Invalid JSON format. Tip: Use minified (single-line) JSON to avoid formatting issues."
          )

        {:noreply, socket}

      _ ->
        socket =
          socket
          |> assign(:orchestrator_prompts_json, json_string)
          |> assign(:orchestrator_json_error, "JSON must be an object/map")
          |> put_flash(:error, "JSON must be an object/map")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("beautify_orchestrator_json", _params, socket) do
    current_json = socket.assigns.orchestrator_prompts_json

    case Jason.decode(current_json) do
      {:ok, prompts} when is_map(prompts) ->
        # Format with pretty printing
        beautified = Jason.encode!(prompts, pretty: true)

        socket =
          socket
          |> assign(:orchestrator_prompts_json, beautified)
          |> assign(:orchestrator_json_error, nil)
          |> put_flash(:info, "JSON beautified successfully")

        {:noreply, socket}

      {:error, %Jason.DecodeError{} = error} ->
        socket =
          socket
          |> assign(
            :orchestrator_json_error,
            "Cannot beautify invalid JSON: #{Exception.message(error)}"
          )
          |> put_flash(:error, "Invalid JSON - fix errors first")

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "JSON must be an object/map")}
    end
  end

  @impl true
  def handle_event("minify_orchestrator_json", _params, socket) do
    current_json = socket.assigns.orchestrator_prompts_json

    case Jason.decode(current_json) do
      {:ok, prompts} when is_map(prompts) ->
        # Format as single line
        minified = Jason.encode!(prompts)

        socket =
          socket
          |> assign(:orchestrator_prompts_json, minified)
          |> assign(:orchestrator_json_error, nil)
          |> put_flash(:info, "JSON minified successfully")

        {:noreply, socket}

      {:error, %Jason.DecodeError{} = error} ->
        socket =
          socket
          |> assign(
            :orchestrator_json_error,
            "Cannot minify invalid JSON: #{Exception.message(error)}"
          )
          |> put_flash(:error, "Invalid JSON - fix errors first")

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "JSON must be an object/map")}
    end
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

        filename =
          "#{System.system_time(:second)}_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}#{ext}"

        dest = Path.join(["priv", "static", "uploads", "backgrounds", filename])

        # Copy file to destination
        File.cp!(path, dest)

        # Ensure file is synced to disk
        {:ok, fd} = :file.open(dest, [:read, :raw])
        :ok = :file.sync(fd)
        :ok = :file.close(fd)

        # Ensure file is readable by the web server
        try do
          File.chmod(dest, 0o644)
        rescue
          _ -> :ok
        end

        # Create database entry
        file_path = "/uploads/backgrounds/#{filename}"

        {:ok, background_image} =
          Chat.create_background_image(%{
            filename: filename,
            original_name: entry.client_name,
            file_path: file_path
          })

        {:ok, background_image}
      end)

    socket =
      if length(uploaded_files) > 0 do
        # Normalize uploaded entries (handle either {:ok, bg} or bg)
        new_images =
          Enum.map(uploaded_files, fn
            {:ok, bg} -> bg
            bg -> bg
          end)

        socket
        |> assign(:background_images, new_images ++ socket.assigns.background_images)
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
    file_path =
      Path.join(["priv", "static"] ++ String.split(background_image.file_path, "/", trim: true))

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
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                    >
                    </path>
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
                  <option value={model} selected={model == @openai_model}>{model}</option>
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
                Status:
                <span class={[
                  "font-medium",
                  String.contains?(@ollama_status, "Connected") && "text-success",
                  !String.contains?(@ollama_status, "Connected") && "text-error"
                ]}>
                  {@ollama_status}
                </span>
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
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                    >
                    </path>
                  </svg>
                  Refresh
                </button>
              </div>
              <%= if length(@ollama_models) > 0 do %>
                <form phx-change="update_ollama_model">
                  <select
                    id="ollama_model"
                    name="ollama_model"
                    class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                  >
                    <%= for model <- @ollama_models do %>
                      <option value={model} selected={model == @ollama_model}>{model}</option>
                    <% end %>
                  </select>
                </form>
                <p class="mt-1 text-sm text-base-content/70">
                  Select the Ollama model to use for chat completions
                </p>
              <% else %>
                <form phx-submit="update_ollama_model">
                  <input
                    type="text"
                    id="ollama_model"
                    name="ollama_model"
                    value={@ollama_model}
                    phx-blur="update_ollama_model"
                    class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                    placeholder="codellama:latest"
                  />
                </form>
                <p class="mt-1 text-sm text-base-content/70">
                  No models found. Run
                  <code class="bg-base-300 px-1 rounded">ollama pull MODEL_NAME</code>
                  to download models, then click Refresh.
                </p>
              <% end %>
            </div>
          </div>
        <% end %>
        <!-- System Prompt (hidden when orchestrator is enabled) -->
        <%= if @enable_prompt_orchestrator != "true" do %>
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
        <% end %>
        <!-- Prompt Orchestrator -->
        <div class="border border-base-300 rounded-lg p-4 bg-base-100">
          <div class="flex items-start justify-between mb-4">
            <div>
              <h3 class="text-lg font-medium text-base-content">Prompt Orchestrator</h3>
              <p class="text-sm text-base-content/70 mt-1">
                Automatically select specialized system prompts based on the user's message content
              </p>
            </div>
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={@enable_prompt_orchestrator == "true"}
                phx-click="toggle_orchestrator"
                class="toggle toggle-primary"
              />
              <span class="text-sm font-medium">
                {if @enable_prompt_orchestrator == "true", do: "Enabled", else: "Disabled"}
              </span>
            </label>
          </div>

          <div class="space-y-4">
            <div>
              <label
                for="orchestrator_prompts"
                class="block text-sm font-medium text-base-content mb-2"
              >
                System Prompts (JSON)
              </label>
              <textarea
                id="orchestrator_prompts"
                rows="12"
                phx-blur="update_orchestrator_prompts"
                class={"w-full px-4 py-2 bg-base-200 text-base-content border rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent font-mono text-sm #{if @orchestrator_json_error, do: "border-error", else: "border-base-300"}"}
                placeholder={
                  ~s({\n  "python": "You are a Python expert...",\n  "python/django": "You are a Django framework expert...",\n  "elixir": "You are an Elixir expert...",\n  "elixir/phoenix": "You are a Phoenix framework expert..."\n})
                }
              ><%= @orchestrator_prompts_json %></textarea>
              
    <!-- Format Buttons -->
              <div class="flex gap-2 mt-2">
                <button
                  type="button"
                  phx-click="beautify_orchestrator_json"
                  class="btn btn-sm btn-outline gap-2"
                  title="Format JSON with indentation for readability"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"
                    >
                    </path>
                  </svg>
                  Beautify JSON
                </button>
                <button
                  type="button"
                  phx-click="minify_orchestrator_json"
                  class="btn btn-sm btn-outline gap-2"
                  title="Compress JSON to single line (recommended to avoid formatting errors)"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                    >
                    </path>
                  </svg>
                  Minify JSON
                </button>
                <div class="flex-1"></div>
                <div class="text-xs text-base-content/50 self-center">
                  {String.length(@orchestrator_prompts_json)} characters
                </div>
              </div>

              <%= if @orchestrator_json_error do %>
                <p class="mt-1 text-sm text-error">
                  {@orchestrator_json_error}
                </p>
              <% else %>
                <p class="mt-1 text-sm text-base-content/70">
                  Define categorized prompts using JSON. Use format:
                  <code class="bg-base-300 px-1 rounded">"category": "prompt text"</code>
                  or <code class="bg-base-300 px-1 rounded">"language/framework": "prompt text"</code>
                  <br />
                  <span class="text-info font-medium">Note:</span>
                  Add a <code class="bg-base-300 px-1 rounded">"default"</code>
                  category to define the fallback prompt when no specific category matches.
                </p>
              <% end %>
            </div>

            <div class="bg-base-200 rounded-lg p-3">
              <div class="text-sm font-medium text-base-content mb-2">Available Categories:</div>
              <%= if @enable_prompt_orchestrator == "true" do %>
                <% categories = ElixirBear.Chat.list_orchestrator_categories() %>
                <div class="flex flex-wrap gap-2">
                  <%= if length(categories) > 0 do %>
                    <%= for category <- categories do %>
                      <span class="badge badge-sm badge-primary">{category}</span>
                    <% end %>
                  <% else %>
                    <span class="badge badge-sm badge-outline">No categories defined yet</span>
                  <% end %>
                </div>
              <% else %>
                <p class="text-sm text-base-content/70 italic">
                  Enable orchestrator to see categories
                </p>
              <% end %>
            </div>

            <div class="bg-info/10 border border-info/20 rounded-lg p-3">
              <div class="flex items-start gap-2">
                <svg
                  class="w-4 h-4 text-info mt-0.5 flex-shrink-0"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  >
                  </path>
                </svg>
                <div class="text-sm text-info">
                  <strong>How it works:</strong>
                  The orchestrator analyzes each user message and selects the most appropriate system prompt.
                  Supports hierarchical categories (e.g.,
                  <code class="bg-base-300 px-1 rounded">python/django</code>
                  → <code class="bg-base-300 px-1 rounded">python</code>
                  → <code class="bg-base-300 px-1 rounded">default</code>).
                  Include a <code class="bg-base-300 px-1 rounded">"default"</code>
                  category in your JSON to define the fallback prompt when no category matches.
                  Uses the same LLM provider as Solution Extraction.
                </div>
              </div>
            </div>
          </div>
        </div>

    <!-- Copy Blocker (Learning Mode) -->
        <div class="border border-base-300 rounded-lg p-4 bg-base-100">
          <div class="flex items-start justify-between mb-2">
            <div>
              <h3 class="text-lg font-medium text-base-content">Copy Blocker (Learning Mode)</h3>
              <p class="text-sm text-base-content/70 mt-1">
                Force active learning by preventing copying of conversation text and code solutions
              </p>
            </div>
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={@enable_copy_blocker == "true"}
                phx-click="toggle_copy_blocker"
                class="toggle toggle-primary"
              />
              <span class="text-sm font-medium">
                {if @enable_copy_blocker == "true", do: "Enabled", else: "Disabled"}
              </span>
            </label>
          </div>

          <div class="bg-warning/10 border border-warning/20 rounded-lg p-3 mt-4">
            <div class="flex items-start gap-2">
              <svg
                class="w-4 h-4 text-warning mt-0.5 flex-shrink-0"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                >
                </path>
              </svg>
              <div class="text-sm text-warning-content">
                <strong>When enabled:</strong>
                Copy buttons will be hidden and text selection will be blocked on all conversation messages. This encourages typing out solutions manually for better learning retention.
              </div>
            </div>
          </div>
        </div>

    <!-- Vision Model Settings -->
        <div class="border border-base-300 rounded-lg p-4 bg-base-100">
          <h3 class="text-lg font-medium text-base-content mb-4">
            Vision Model (Image Understanding)
          </h3>
          <p class="text-sm text-base-content/70 mb-4">
            Separate model for analyzing images. Always uses OpenAI API with the API key configured above.
          </p>

          <div>
            <label for="vision_model" class="block text-sm font-medium text-base-content mb-2">
              Vision Model
            </label>
            <select
              id="vision_model"
              name="value"
              phx-change="update_vision_model"
              class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
            >
              <option value="gpt-4o" selected={"gpt-4o" == @vision_model}>
                gpt-4o (Recommended)
              </option>
              <option value="gpt-4o-mini" selected={"gpt-4o-mini" == @vision_model}>
                gpt-4o-mini (Faster, cheaper)
              </option>
              <option value="gpt-4-turbo" selected={"gpt-4-turbo" == @vision_model}>
                gpt-4-turbo
              </option>
              <option value="gpt-4-vision-preview" selected={"gpt-4-vision-preview" == @vision_model}>
                gpt-4-vision-preview
              </option>
            </select>
            <p class="mt-1 text-sm text-base-content/70">
              Model used for analyzing images you attach to messages
            </p>
          </div>
        </div>
        
    <!-- Solution Extraction Settings -->
        <div class="border border-base-300 rounded-lg p-4 bg-base-100">
          <h3 class="text-lg font-medium text-base-content mb-2">
            Solution Extraction (Treasure Trove)
          </h3>
          <p class="text-sm text-base-content/70 mb-4">
            Configure the LLM used to extract metadata from code solutions. This extracts topics, difficulty, and descriptions from conversations.
          </p>
          
    <!-- Provider Selection -->
          <div class="mb-4">
            <label class="block text-sm font-medium text-base-content mb-3">
              Extraction LLM Provider
            </label>
            <div class="space-y-2">
              <label class="flex items-center gap-3 cursor-pointer">
                <input
                  type="radio"
                  name="solution_extraction_provider"
                  value="ollama"
                  checked={@solution_extraction_provider == "ollama"}
                  phx-click="change_solution_extraction_provider"
                  phx-value-provider="ollama"
                  class="w-4 h-4 text-primary"
                />
                <span class="text-base-content">Ollama (Local, Free)</span>
              </label>
              <label class="flex items-center gap-3 cursor-pointer">
                <input
                  type="radio"
                  name="solution_extraction_provider"
                  value="openai"
                  checked={@solution_extraction_provider == "openai"}
                  phx-click="change_solution_extraction_provider"
                  phx-value-provider="openai"
                  class="w-4 h-4 text-primary"
                />
                <span class="text-base-content">OpenAI</span>
              </label>
            </div>
          </div>
          
    <!-- Model Selection based on Provider -->
          <%= if @solution_extraction_provider == "ollama" do %>
            <div>
              <label
                for="solution_extraction_ollama_model"
                class="block text-sm font-medium text-base-content mb-2"
              >
                Ollama Model
              </label>
              <%= if length(@ollama_models) > 0 do %>
                <select
                  id="solution_extraction_ollama_model"
                  name="value"
                  phx-change="update_solution_extraction_ollama_model"
                  class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                >
                  <%= for model <- @ollama_models do %>
                    <option value={model} selected={model == @solution_extraction_ollama_model}>
                      {model}
                    </option>
                  <% end %>
                </select>
                <p class="mt-1 text-sm text-base-content/70">
                  Recommended: Small, fast models like llama3.2, qwen2.5:3b, or phi3
                </p>
              <% else %>
                <input
                  type="text"
                  id="solution_extraction_ollama_model"
                  value={@solution_extraction_ollama_model}
                  phx-blur="update_solution_extraction_ollama_model"
                  class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
                  placeholder="llama3.2"
                />
                <p class="mt-1 text-sm text-base-content/70">
                  No Ollama models found. Ensure Ollama is running and refresh models above.
                </p>
              <% end %>
            </div>
          <% else %>
            <div>
              <label
                for="solution_extraction_openai_model"
                class="block text-sm font-medium text-base-content mb-2"
              >
                OpenAI Model
              </label>
              <select
                id="solution_extraction_openai_model"
                name="value"
                phx-change="update_solution_extraction_openai_model"
                class="w-full px-4 py-2 bg-base-200 text-base-content border border-base-300 rounded-lg focus:ring-2 focus:ring-primary focus:border-transparent"
              >
                <%= for model <- @openai_models do %>
                  <option value={model} selected={model == @solution_extraction_openai_model}>
                    {model}
                  </option>
                <% end %>
              </select>
              <p class="mt-1 text-sm text-base-content/70">
                Used for extracting metadata. Faster, cheaper models like gpt-4o-mini recommended.
              </p>
            </div>
          <% end %>
          
    <!-- Divider -->
          <div class="divider"></div>
          
    <!-- Solution Router Settings -->
          <div class="mt-6">
            <h4 class="text-md font-medium text-base-content mb-2">Solution Router</h4>
            <p class="text-sm text-base-content/70 mb-4">
              Automatically check Treasure Trove for similar solutions before calling the main LLM. Save time and API costs by reusing existing solutions.
            </p>
            
    <!-- Enable/Disable Toggle -->
            <div class="mb-4">
              <label class="flex items-center gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={@enable_solution_router == "true"}
                  phx-click="toggle_solution_router"
                  class="toggle toggle-primary"
                />
                <span class="text-base-content">
                  Enable Solution Router {if @enable_solution_router == "true", do: "✓", else: ""}
                </span>
              </label>
              <p class="mt-1 text-sm text-base-content/70 ml-12">
                When enabled, checks Treasure Trove for similar solutions before asking the LLM.
              </p>
            </div>
            
    <!-- Similarity Threshold -->
            <%= if @enable_solution_router == "true" do %>
              <div>
                <label
                  for="solution_router_threshold"
                  class="block text-sm font-medium text-base-content mb-2"
                >
                  Similarity Threshold:
                  <span id="threshold-display">
                    {Float.parse(@solution_router_threshold) |> elem(0) |> Float.round(2)}
                  </span>
                </label>
                <input
                  type="range"
                  id="solution_router_threshold"
                  name="value"
                  min="0.5"
                  max="0.95"
                  step="0.05"
                  value={@solution_router_threshold}
                  phx-hook="ThresholdSlider"
                  data-display-id="threshold-display"
                  class="range range-primary"
                />
                <div class="flex justify-between text-xs text-base-content/70 mt-1">
                  <span>More suggestions (0.5)</span>
                  <span>Fewer, more precise (0.95)</span>
                </div>
                <p class="mt-2 text-sm text-base-content/70">
                  Higher values = more confident matches required. Lower values = more suggestions (may include less relevant matches).
                </p>
              </div>
            <% end %>
          </div>
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
                  <.live_file_input
                    upload={@uploads.background_image}
                    class="file-input file-input-bordered w-full"
                  />
                  <%= for entry <- @uploads.background_image.entries do %>
                    <div class="mt-3 flex items-center gap-3">
                      <.live_img_preview
                        entry={entry}
                        class="w-32 h-20 object-cover rounded-md border border-base-300"
                      />
                      <div class="text-sm text-base-content/70">
                        <div class="font-medium">{entry.client_name}</div>
                        <div class="text-xs">Uploading…</div>
                      </div>
                    </div>
                  <% end %>
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
                  <div class={"relative group rounded-lg overflow-hidden border-2 bg-base-200 #{if @selected_background && @selected_background.id == bg_image.id, do: "border-primary shadow-lg", else: "border-base-300"}"}>
                    <div class="relative bg-card">
                      <div class="absolute inset-0 skeleton bg-base-200 animate-pulse hidden"></div>
                      <picture>
                        <% preview_src =
                          @pending_previews[bg_image.original_name] ||
                            "#{bg_image.file_path}?v=#{bg_image.id}" %>
                        <img
                          src={preview_src}
                          alt={bg_image.original_name}
                          class="w-full h-32 object-cover opacity-0 transition-opacity duration-200"
                          onload="this.classList.remove('opacity-0'); this.classList.add('opacity-100'); var s=this.closest('.bg-card') && this.closest('.bg-card').querySelector('.skeleton'); if(s) s.classList.add('hidden');"
                          onerror="this.src='/images/logo.svg'"
                        />
                      </picture>
                    </div>
                    <div class="absolute inset-0 bg-black/0 group-hover:bg-black/50 transition-all flex items-center justify-center gap-2">
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
