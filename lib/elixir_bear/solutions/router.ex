defmodule ElixirBear.Solutions.Router do
  @moduledoc """
  Routes user queries to existing solutions in the Treasure Trove.

  Uses LLM-based similarity matching to find relevant solutions before
  making expensive inference calls to the main chat LLM.
  """

  require Logger
  alias ElixirBear.Solutions
  alias ElixirBear.Chat
  alias ElixirBear.{Ollama, OpenAI}

  @doc """
  Finds the best matching solution for a user query.

  Returns:
  - {:ok, solution, confidence} if a match is found above threshold
  - {:error, :no_match} if no match meets the threshold
  - {:error, :router_disabled} if router is disabled
  - {:error, reason} for other errors
  """
  def find_matching_solution(user_query) do
    # Check if router is enabled
    enabled = Chat.get_setting_value("enable_solution_router") || "true"

    if enabled == "false" do
      {:error, :router_disabled}
    else
      threshold_str = Chat.get_setting_value("solution_router_threshold") || "0.75"
      threshold = String.to_float(threshold_str)

      # Get all solutions
      solutions = Solutions.list_solutions()

      if Enum.empty?(solutions) do
        {:error, :no_solutions_available}
      else
        # Use LLM to find best match
        find_best_match_with_llm(user_query, solutions, threshold)
      end
    end
  end

  # Private functions

  defp find_best_match_with_llm(user_query, solutions, threshold) do
    provider = Chat.get_setting_value("solution_extraction_provider") || "ollama"

    case provider do
      "ollama" -> match_with_ollama(user_query, solutions, threshold)
      "openai" -> match_with_openai(user_query, solutions, threshold)
      _ -> {:error, :invalid_provider}
    end
  end

  defp match_with_ollama(user_query, solutions, threshold) do
    model = Chat.get_setting_value("solution_extraction_ollama_model") || "llama3.2"
    url = Chat.get_setting_value("ollama_url") || "http://localhost:11434"

    prompt = build_matching_prompt(user_query, solutions)

    messages = [
      %{role: "system", content: matching_system_prompt()},
      %{role: "user", content: prompt}
    ]

    Logger.info("Router: Checking #{length(solutions)} solutions with Ollama model: #{model}")

    case Ollama.chat_completion(messages, model: model, url: url, temperature: 0.1) do
      {:ok, response} ->
        parse_matching_response(response, solutions, threshold)

      {:error, reason} ->
        Logger.error("Router: Ollama matching failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp match_with_openai(user_query, solutions, threshold) do
    model = Chat.get_setting_value("solution_extraction_openai_model") || "gpt-4o-mini"
    api_key = Chat.get_setting_value("openai_api_key")

    if !api_key do
      {:error, :missing_api_key}
    else
      prompt = build_matching_prompt(user_query, solutions)

      messages = [
        %{role: "system", content: matching_system_prompt()},
        %{role: "user", content: prompt}
      ]

      Logger.info("Router: Checking #{length(solutions)} solutions with OpenAI model: #{model}")

      case OpenAI.chat_completion(api_key, messages, model: model, temperature: 0.1) do
        {:ok, response} ->
          parse_matching_response(response, solutions, threshold)

        {:error, reason} ->
          Logger.error("Router: OpenAI matching failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp matching_system_prompt do
    """
    You are a solution matching assistant. Your job is to determine if a user's question matches any of the saved solutions provided.

    You must respond ONLY with valid JSON in this exact format:
    {
      "best_match_id": <solution_id or null>,
      "confidence": <number between 0.0 and 1.0>,
      "reasoning": "Brief explanation of why this matches or why no match was found"
    }

    Guidelines for matching:
    - Consider semantic similarity, not just exact word matches
    - A question asking "how to do X" matches a solution that teaches X
    - Different phrasing of the same concept should match (e.g., "test a function" = "write unit tests")
    - Confidence should reflect how well the solution answers the user's question
    - If multiple solutions match, choose the best one
    - If no solution is relevant, set best_match_id to null and confidence to 0.0

    Respond with ONLY the JSON, no other text.
    """
  end

  defp build_matching_prompt(user_query, solutions) do
    solutions_text =
      solutions
      |> Enum.map(fn solution ->
        topics =
          Enum.filter(solution.tags, fn tag -> tag.tag_type == "topic" end)
          |> Enum.map(& &1.tag_value)
          |> Enum.join(", ")

        difficulty =
          Enum.find(solution.tags, fn tag -> tag.tag_type == "difficulty" end)
          |> case do
            nil -> "unknown"
            tag -> tag.tag_value
          end

        """
        ID: #{solution.id}
        Title: #{solution.title || "Untitled"}
        Topics: #{topics}
        Difficulty: #{difficulty}
        Original Question: #{solution.user_query}
        Description: #{get_in(solution.metadata, ["description"]) || "No description"}
        """
      end)
      |> Enum.join("\n---\n")

    """
    User's New Question:
    "#{user_query}"

    Saved Solutions in Treasure Trove:
    #{solutions_text}

    Find the best matching solution for the user's question. Consider semantic meaning, not just keywords.
    """
  end

  defp parse_matching_response(response, solutions, threshold) do
    # Try to extract JSON from the response
    json_text = extract_json_from_text(response)

    case Jason.decode(json_text) do
      {:ok, parsed} ->
        match_id = parsed["best_match_id"]
        confidence = parsed["confidence"] || 0.0
        reasoning = parsed["reasoning"] || ""

        Logger.info("Router: Match result - ID: #{inspect(match_id)}, Confidence: #{confidence}")
        Logger.debug("Router: Reasoning: #{reasoning}")

        cond do
          is_nil(match_id) ->
            {:error, :no_match}

          confidence < threshold ->
            Logger.info(
              "Router: Match found but confidence #{confidence} below threshold #{threshold}"
            )

            {:error, :below_threshold}

          true ->
            # Find the solution
            solution = Enum.find(solutions, fn s -> s.id == match_id end)

            if solution do
              {:ok, solution, confidence}
            else
              Logger.error("Router: Solution ID #{match_id} not found in solutions list")
              {:error, :solution_not_found}
            end
        end

      {:error, reason} ->
        Logger.error("Router: Failed to parse LLM response as JSON: #{inspect(reason)}")
        Logger.debug("Router: Response was: #{response}")
        {:error, :invalid_json_response}
    end
  end

  defp extract_json_from_text(text) do
    # Sometimes LLMs wrap JSON in markdown code blocks or add extra text
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
