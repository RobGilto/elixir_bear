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

    # Normalize messages to ensure content is always a string
    normalized_messages = normalize_messages(messages)

    body =
      %{
        model: model,
        messages: normalized_messages,
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

    # Normalize messages to ensure content is always a string
    normalized_messages = normalize_messages(messages)

    body =
      %{
        model: model,
        messages: normalized_messages,
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
    Logger.debug("Sending request to Ollama: #{api_url}")

    case Req.post(api_url,
           body: body,
           headers: headers,
           into: fn {:data, data}, {req, resp} ->
             Logger.debug("Received #{byte_size(data)} bytes from Ollama")
             process_stream_chunk(data, callback)
             {:cont, {req, resp}}
           end
         ) do
      {:ok, response} ->
        Logger.debug("Ollama request completed: #{inspect(response.status)}")
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

  # Normalizes messages to ensure content is always a string.
  # Ollama doesn't support multimodal content arrays, so we extract text from array-formatted content.
  defp normalize_messages(messages) do
    Enum.map(messages, &normalize_message/1)
  end

  defp normalize_message(%{"content" => content} = message) when is_list(content) do
    # Extract text from multimodal content array
    text_content =
      content
      |> Enum.filter(fn part -> part["type"] == "text" end)
      |> Enum.map(fn part -> part["text"] end)
      |> Enum.join("\n")

    %{message | "content" => text_content}
  end

  defp normalize_message(%{content: content} = message) when is_list(content) do
    # Handle atom keys as well
    text_content =
      content
      |> Enum.filter(fn part ->
        is_map(part) && (part["type"] == "text" || part[:type] == "text")
      end)
      |> Enum.map(fn part -> part["text"] || part[:text] end)
      |> Enum.join("\n")

    %{message | content: text_content}
  end

  defp normalize_message(message) do
    # Content is already a string, return as-is
    message
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
              Logger.debug("Calling callback with content: #{String.slice(content, 0..50)}")
              callback.(content)

            {:ok, %{"done" => true}} ->
              Logger.debug("Received done signal from Ollama")
              :ok

            {:ok, decoded} ->
              Logger.warning("Unexpected Ollama response format: #{inspect(decoded)}")
              :ok

            {:error, error} ->
              Logger.error("Failed to parse Ollama JSON: #{inspect(error)}, line: #{json_line}")
              :ok
          end
      end
    end)
  end
end
