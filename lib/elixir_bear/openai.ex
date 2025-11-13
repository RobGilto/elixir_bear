defmodule ElixirBear.OpenAI do
  @moduledoc """
  OpenAI API client for chat completions.
  """

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"

  @doc """
  Sends a chat completion request to OpenAI API.

  ## Parameters
    - api_key: OpenAI API key
    - messages: List of message maps with :role and :content
    - opts: Optional parameters like model, temperature, etc.

  ## Returns
    - {:ok, response_content} on success
    - {:error, reason} on failure
  """
  def chat_completion(api_key, messages, opts \\ []) do
    model = Keyword.get(opts, :model, "gpt-3.5-turbo")
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)
    stream = Keyword.get(opts, :stream, false)

    body =
      %{
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: stream
      }
      |> Jason.encode!()

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(@api_url, body: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        extract_message_content(response_body)

      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
        {:error, "API returned status #{status}: #{extract_error_message(body)}"}

      {:error, reason} ->
        Logger.error("OpenAI API request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Streams a chat completion from OpenAI API.

  ## Parameters
    - api_key: OpenAI API key
    - messages: List of message maps with :role and :content
    - callback: Function to call with each chunk of content
    - opts: Optional parameters like model, temperature, etc.

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def stream_chat_completion(api_key, messages, callback, opts \\ []) do
    model = Keyword.get(opts, :model, "gpt-3.5-turbo")
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    body =
      %{
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: true
      }
      |> Jason.encode!()

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    # Use Req with into option for streaming
    case Req.post(@api_url,
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
        Logger.error("OpenAI streaming failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_message_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, content}
  end

  defp extract_message_content(body) do
    {:error, "Unexpected response format: #{inspect(body)}"}
  end

  defp extract_error_message(%{"error" => %{"message" => message}}), do: message
  defp extract_error_message(body), do: inspect(body)

  @doc """
  Lists available OpenAI models.

  ## Parameters
    - api_key: OpenAI API key

  ## Returns
    - {:ok, models} where models is a list of model IDs
    - {:error, reason} on failure
  """
  def list_models(api_key) do
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case Req.get("https://api.openai.com/v1/models", headers: headers) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        # Filter for chat models and sort by popularity
        chat_models =
          models
          |> Enum.filter(fn model ->
            id = model["id"]
            String.contains?(id, "gpt") && !String.contains?(id, "instruct")
          end)
          |> Enum.map(fn model -> model["id"] end)
          |> Enum.sort()

        {:ok, chat_models}

      {:ok, %{status: status, body: body}} ->
        {:error, "API returned status #{status}: #{extract_error_message(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Returns a list of commonly used OpenAI models (fallback when API is unavailable).
  """
  def default_models do
    [
      "gpt-4o",
      "gpt-4o-mini",
      "gpt-4-turbo",
      "gpt-4",
      "gpt-3.5-turbo"
    ]
  end

  defp process_stream_chunk(data, callback) do
    data
    |> String.split("\n")
    |> Enum.each(fn line ->
      case String.trim(line) do
        "data: [DONE]" ->
          :ok

        "data: " <> json_data ->
          case Jason.decode(json_data) do
            {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} ->
              callback.(content)

            _ ->
              :ok
          end

        _ ->
          :ok
      end
    end)
  end
end
