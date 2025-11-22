defmodule ElixirBear.SettingsCache do
  use GenServer
  require Logger

  @cache_ttl :timer.minutes(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_all_settings do
    GenServer.call(__MODULE__, :get_all_settings)
  end

  def get_ollama_models(url) do
    GenServer.call(__MODULE__, {:get_ollama_models, url})
  end

  def get_openai_models(api_key) do
    GenServer.call(__MODULE__, {:get_openai_models, api_key})
  end

  def invalidate do
    GenServer.cast(__MODULE__, :invalidate)
  end

  @impl true
  def init(_) do
    :ets.new(:settings_cache, [:set, :protected, :named_table])
    {:ok, %{}}
  end

  @impl true
  def handle_call(:get_all_settings, _from, state) do
    case :ets.lookup(:settings_cache, :all_settings) do
      [{:all_settings, settings, timestamp}] ->
        if System.monotonic_time(:millisecond) - timestamp < @cache_ttl do
          {:reply, settings, state}
        else
          settings = load_all_settings()
          :ets.insert(:settings_cache, {:all_settings, settings, System.monotonic_time(:millisecond)})
          {:reply, settings, state}
        end

      [] ->
        settings = load_all_settings()
        :ets.insert(:settings_cache, {:all_settings, settings, System.monotonic_time(:millisecond)})
        {:reply, settings, state}
    end
  end

  @impl true
  def handle_call({:get_ollama_models, url}, _from, state) do
    cache_key = {:ollama_models, url}

    case :ets.lookup(:settings_cache, cache_key) do
      [{^cache_key, models, timestamp}] ->
        if System.monotonic_time(:millisecond) - timestamp < @cache_ttl do
          {:reply, models, state}
        else
          models = fetch_ollama_models(url)
          :ets.insert(:settings_cache, {cache_key, models, System.monotonic_time(:millisecond)})
          {:reply, models, state}
        end

      [] ->
        models = fetch_ollama_models(url)
        :ets.insert(:settings_cache, {cache_key, models, System.monotonic_time(:millisecond)})
        {:reply, models, state}
    end
  end

  @impl true
  def handle_call({:get_openai_models, api_key}, _from, state) do
    cache_key = {:openai_models, api_key}

    case :ets.lookup(:settings_cache, cache_key) do
      [{^cache_key, models, timestamp}] ->
        if System.monotonic_time(:millisecond) - timestamp < @cache_ttl do
          {:reply, models, state}
        else
          models = fetch_openai_models(api_key)
          :ets.insert(:settings_cache, {cache_key, models, System.monotonic_time(:millisecond)})
          {:reply, models, state}
        end

      [] ->
        models = fetch_openai_models(api_key)
        :ets.insert(:settings_cache, {cache_key, models, System.monotonic_time(:millisecond)})
        {:reply, models, state}
    end
  end

  @impl true
  def handle_cast(:invalidate, state) do
    :ets.delete_all_objects(:settings_cache)
    {:noreply, state}
  end

  defp load_all_settings do
    alias ElixirBear.Chat

    %{
      api_key: Chat.get_setting_value("openai_api_key") || "",
      system_prompt: Chat.get_setting_value("system_prompt") || "",
      llm_provider: Chat.get_setting_value("llm_provider") || "openai",
      openai_model: Chat.get_setting_value("openai_model") || "gpt-3.5-turbo",
      vision_model: Chat.get_setting_value("vision_model") || "gpt-4o",
      ollama_model: Chat.get_setting_value("ollama_model") || "codellama:latest",
      ollama_url: Chat.get_setting_value("ollama_url") || "http://localhost:11434",
      solution_extraction_provider:
        Chat.get_setting_value("solution_extraction_provider") || "ollama",
      solution_extraction_ollama_model:
        Chat.get_setting_value("solution_extraction_ollama_model") || "llama3.2",
      solution_extraction_openai_model:
        Chat.get_setting_value("solution_extraction_openai_model") || "gpt-4o-mini",
      enable_solution_router: Chat.get_setting_value("enable_solution_router") || "true",
      solution_router_threshold: Chat.get_setting_value("solution_router_threshold") || "0.75",
      enable_prompt_orchestrator:
        Chat.get_setting_value("enable_prompt_orchestrator") || "false",
      orchestrator_prompts_json: Chat.get_setting_value("orchestrator_prompts") || ~s({}),
      enable_copy_blocker: Chat.get_setting_value("enable_copy_blocker") || "true"
    }
  end

  defp fetch_ollama_models(url) do
    alias ElixirBear.Ollama

    case Ollama.check_connection(url: url) do
      {:ok, version} ->
        models =
          case Ollama.list_models(url: url) do
            {:ok, models} -> models
            {:error, _} -> []
          end

        {:ok, {"Connected (version: #{version})", models}}

      {:error, _} ->
        {:ok, {"Not connected", []}}
    end
  end

  defp fetch_openai_models(api_key) do
    alias ElixirBear.OpenAI

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
  end
end
