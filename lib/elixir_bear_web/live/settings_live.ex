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
