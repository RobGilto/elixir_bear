defmodule ElixirBear.Solutions.LLMExtractor do
  @moduledoc """
  Extracts metadata from solutions using an LLM.
  Generates title, topics, difficulty, and description.
  """

  require Logger
  alias ElixirBear.Chat
  alias ElixirBear.{Ollama, OpenAI}

  @doc """
  Extracts metadata from a solution package using the configured extraction LLM.

  Returns {:ok, metadata} or {:error, reason}

  The metadata map contains:
  - title: A concise title for the solution
  - topics: List of topic tags (e.g., ["pattern_matching", "functions"])
  - difficulty: "beginner", "intermediate", or "advanced"
  - description: Brief explanation of what the solution teaches
  - languages: List of programming languages used
  """
  def extract_metadata(solution_package) do
    provider = Chat.get_setting_value("solution_extraction_provider") || "ollama"

    case provider do
      "ollama" -> extract_with_ollama(solution_package)
      "openai" -> extract_with_openai(solution_package)
      _ -> {:error, :invalid_provider}
    end
  end

  # Private functions

  defp extract_with_ollama(package) do
    model = Chat.get_setting_value("solution_extraction_ollama_model") || "llama3.2"
    url = Chat.get_setting_value("ollama_url") || "http://localhost:11434"

    prompt = build_extraction_prompt(package)

    messages = [
      %{role: "system", content: system_prompt()},
      %{role: "user", content: prompt}
    ]

    Logger.info("Extracting metadata with Ollama model: #{model}")

    case Ollama.chat_completion(messages, model: model, url: url, temperature: 0.3) do
      {:ok, response} ->
        parse_llm_response(response)

      {:error, reason} ->
        Logger.error("Ollama extraction failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_with_openai(package) do
    model = Chat.get_setting_value("solution_extraction_openai_model") || "gpt-4o-mini"
    api_key = Chat.get_setting_value("openai_api_key")

    if !api_key do
      {:error, :missing_api_key}
    else
      prompt = build_extraction_prompt(package)

      messages = [
        %{role: "system", content: system_prompt()},
        %{role: "user", content: prompt}
      ]

      Logger.info("Extracting metadata with OpenAI model: #{model}")

      case OpenAI.chat_completion(api_key, messages, model: model, temperature: 0.3) do
        {:ok, response} ->
          parse_llm_response(response)

        {:error, reason} ->
          Logger.error("OpenAI extraction failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp system_prompt do
    """
    You are a metadata extraction assistant for an Elixir learning platform. Your job is to analyze user questions and assistant answers to extract structured metadata.

    You must respond ONLY with valid JSON in this exact format:
    {
      "title": "Brief descriptive title (max 60 chars)",
      "topics": ["topic1", "topic2", "topic3"],
      "difficulty": "beginner|intermediate|advanced",
      "description": "One sentence explaining what this solution teaches",
      "languages": ["elixir", "javascript", etc]
    }

    Guidelines:
    - Title should be concise and descriptive (e.g., "Pattern Matching in Function Heads")
    - Topics should be lowercase, underscore-separated tags (e.g., "pattern_matching", "recursion", "genserver")
    - Include 2-5 relevant topics
    - Difficulty should match the complexity of the concepts
    - Description should be a single clear sentence
    - Languages should match what was actually used in the code blocks

    Respond with ONLY the JSON, no other text.
    """
  end

  defp build_extraction_prompt(package) do
    """
    Analyze this Q&A exchange and extract metadata:

    **User Question:**
    #{package.solution_attrs.user_query}

    **Assistant Answer:**
    #{String.slice(package.solution_attrs.answer_content, 0..2000)}

    **Code Blocks Found:**
    #{Enum.count(package.code_blocks_attrs)} code blocks in languages: #{Enum.map_join(package.metadata.languages, ", ", & &1)}

    Extract and return the metadata as JSON.
    """
  end

  defp parse_llm_response(response) do
    # Try to extract JSON from the response
    json_text = extract_json_from_text(response)

    case Jason.decode(json_text) do
      {:ok, parsed} ->
        metadata = %{
          title: parsed["title"],
          topics: parsed["topics"] || [],
          difficulty: parsed["difficulty"],
          description: parsed["description"],
          languages: parsed["languages"] || []
        }

        {:ok, metadata}

      {:error, reason} ->
        Logger.error("Failed to parse LLM response as JSON: #{inspect(reason)}")
        Logger.debug("Response was: #{response}")
        {:error, :invalid_json_response}
    end
  end

  defp extract_json_from_text(text) do
    # Sometimes LLMs wrap JSON in markdown code blocks or add extra text
    # Try to extract just the JSON part
    text = String.trim(text)

    cond do
      String.starts_with?(text, "```json") ->
        text
        |> String.replace_prefix("```json", "")
        |> String.replace_suffix("```", "")
        |> String.trim()

      String.starts_with?(text, "```") ->
        text
        |> String.replace_prefix("```", "")
        |> String.replace_suffix("```", "")
        |> String.trim()

      String.contains?(text, "{") ->
        # Extract from first { to last }
        start_idx = String.graphemes(text) |> Enum.find_index(&(&1 == "{"))
        end_idx = String.graphemes(text) |> Enum.reverse() |> Enum.find_index(&(&1 == "}"))

        if start_idx && end_idx do
          end_idx = String.length(text) - end_idx
          String.slice(text, start_idx..(end_idx - 1))
        else
          text
        end

      true ->
        text
    end
  end
end
