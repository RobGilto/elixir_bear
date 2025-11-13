defmodule ElixirBear.Ollama do
  @moduledoc """
  Ollama API client for chat completions.
  Ollama is a local LLM runner that provides OpenAI-compatible APIs.
  """

  require Logger

  @doc """
  Sends a chat completion request to Ollama API.

  ## Parameters
    - messages: List of message maps with :role and :content
    - opts: Optional parameters like model, url, temperature, etc.

  ## Returns
    - {:ok, response_content} on success
    - {:error, reason} on failure
  """
  def chat_completion(messages, opts \\ []) do
    model = Keyword.get(opts, :model, "llama3.2")
    url = Keyword.get(opts, :url, "http://localhost:11434")
    temperature = Keyword.get(opts, :temperature, 0.7)

    api_url = "#{url}/api/chat"

    body =
      %{
        model: model,
        messages: messages,
        stream: false,
        options: %{
          temperature: temperature
        }
      }
      |> Jason.encode!()

    headers = [
      {"Content-Type", "application/json"}
    ]

    case Req.post(api_url, body: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        extract_message_content(response_body)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Ollama API error: #{status} - #{inspect(body)}")
        {:error, "API returned status #{status}: #{extract_error_message(body)}"}

      {:error, reason} ->
        Logger.error("Ollama API request failed: #{inspect(reason)}")
        {:error, "Request failed. Is Ollama running? #{inspect(reason)}"}
    end
  end

  @doc """
  Streams a chat completion from Ollama API.

  ## Parameters
    - messages: List of message maps with :role and :content
    - callback: Function to call with each chunk of content
    - opts: Optional parameters like model, url, temperature, etc.

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def stream_chat_completion(messages, callback, opts \\ []) do
    model = Keyword.get(opts, :model, "llama3.2")
    url = Keyword.get(opts, :url, "http://localhost:11434")
    temperature = Keyword.get(opts, :temperature, 0.7)

    api_url = "#{url}/api/chat"

    body =
      %{
        model: model,
        messages: messages,
        stream: true,
        options: %{
          temperature: temperature
        }
      }
      |> Jason.encode!()

    headers = [
      {"Content-Type", "application/json"}
    ]

    # Use Req with into option for streaming
    case Req.post(api_url,
           body: body,
           headers: headers,
           into: fn {:data, data}, {req, resp} ->
             process_stream_chunk(data, callback)
             {:cont, {req, resp}}
           end
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Ollama streaming failed: #{inspect(reason)}")
        {:error, "Streaming failed. Is Ollama running? #{inspect(reason)}"}
    end
  end

  @doc """
  Check if Ollama server is running and accessible.

  ## Parameters
    - opts: Optional parameters like url

  ## Returns
    - {:ok, version} on success
    - {:error, reason} on failure
  """
  def check_connection(opts \\ []) do
    url = Keyword.get(opts, :url, "http://localhost:11434")
    api_url = "#{url}/api/version"

    case Req.get(api_url) do
      {:ok, %{status: 200, body: body}} ->
        version = Map.get(body, "version", "unknown")
        {:ok, version}

      {:error, reason} ->
        {:error, "Cannot connect to Ollama server: #{inspect(reason)}"}
    end
  end

  @doc """
  List available models from Ollama.

  ## Parameters
    - opts: Optional parameters like url

  ## Returns
    - {:ok, models} on success where models is a list of model names
    - {:error, reason} on failure
  """
  def list_models(opts \\ []) do
    url = Keyword.get(opts, :url, "http://localhost:11434")
    api_url = "#{url}/api/tags"

    case Req.get(api_url) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        model_names = Enum.map(models, fn model -> model["name"] end)
        {:ok, model_names}

      {:ok, %{status: status, body: body}} ->
        {:error, "API returned status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Cannot list models: #{inspect(reason)}"}
    end
  end

  defp extract_message_content(%{"message" => %{"content" => content}}) do
    {:ok, content}
  end

  defp extract_message_content(body) do
    {:error, "Unexpected response format: #{inspect(body)}"}
  end

  defp extract_error_message(%{"error" => message}), do: message
  defp extract_error_message(body), do: inspect(body)

  defp process_stream_chunk(data, callback) do
    data
    |> String.split("\n")
    |> Enum.each(fn line ->
      case String.trim(line) do
        "" ->
          :ok

        json_line ->
          case Jason.decode(json_line) do
            {:ok, %{"message" => %{"content" => content}}} ->
              callback.(content)

            {:ok, %{"done" => true}} ->
              :ok

            _ ->
              :ok
          end
      end
    end)
  end
end
