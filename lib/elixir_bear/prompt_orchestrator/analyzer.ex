defmodule ElixirBear.PromptOrchestrator.Analyzer do
  @moduledoc """
  Analyzes user prompts and selects the most appropriate system prompt category.

  Uses LLM-based classification to intelligently route prompts to specialized
  system prompts based on content, context, and available categories.
  """

  require Logger
  alias ElixirBear.Chat
  alias ElixirBear.{Ollama, OpenAI}

  @doc """
  Analyzes a user message and selects the best matching system prompt category.

  Returns:
  - {:ok, category, confidence} if a category is selected
  - {:error, :no_match} if no specific category matches (should use default)
  - {:error, :orchestrator_disabled} if orchestrator is disabled
  - {:error, reason} for other errors
  """
  def analyze_and_select_prompt(user_message, available_categories \\ nil) do
    # Check if orchestrator is enabled
    if !Chat.orchestrator_enabled?() do
      {:error, :orchestrator_disabled}
    else
      categories = available_categories || Chat.list_orchestrator_categories()

      if Enum.empty?(categories) do
        # No categories configured, use default
        {:error, :no_categories_available}
      else
        # Use LLM to categorize the prompt
        categorize_with_llm(user_message, categories)
      end
    end
  end

  # Private functions

  defp categorize_with_llm(user_message, categories) do
    # Use the same provider as solution extraction
    provider = Chat.get_setting_value("solution_extraction_provider") || "ollama"

    case provider do
      "ollama" -> categorize_with_ollama(user_message, categories)
      "openai" -> categorize_with_openai(user_message, categories)
      _ -> {:error, :invalid_provider}
    end
  end

  defp categorize_with_ollama(user_message, categories) do
    model = Chat.get_setting_value("solution_extraction_ollama_model") || "llama3.2"
    url = Chat.get_setting_value("ollama_url") || "http://localhost:11434"

    prompt = build_categorization_prompt(user_message, categories)

    messages = [
      %{role: "system", content: categorization_system_prompt()},
      %{role: "user", content: prompt}
    ]

    Logger.info("Orchestrator: Categorizing prompt with Ollama model: #{model}")

    case Ollama.chat_completion(messages, model: model, url: url, temperature: 0.1) do
      {:ok, response} ->
        parse_categorization_response(response, categories)

      {:error, reason} ->
        Logger.error("Orchestrator: Ollama categorization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp categorize_with_openai(user_message, categories) do
    model = Chat.get_setting_value("solution_extraction_openai_model") || "gpt-4o-mini"
    api_key = Chat.get_setting_value("openai_api_key")

    if !api_key do
      {:error, :missing_api_key}
    else
      prompt = build_categorization_prompt(user_message, categories)

      messages = [
        %{role: "system", content: categorization_system_prompt()},
        %{role: "user", content: prompt}
      ]

      Logger.info("Orchestrator: Categorizing prompt with OpenAI model: #{model}")

      case OpenAI.chat_completion(api_key, messages, model: model, temperature: 0.1) do
        {:ok, response} ->
          parse_categorization_response(response, categories)

        {:error, reason} ->
          Logger.error("Orchestrator: OpenAI categorization failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp categorization_system_prompt do
    """
    You are a prompt categorization assistant. Your job is to analyze user messages and select the most appropriate category for system prompt selection.

    You must respond ONLY with valid JSON in this exact format:
    {
      "category": "<category_name or null>",
      "confidence": <number between 0.0 and 1.0>,
      "reasoning": "Brief explanation of why this category was selected"
    }

    Guidelines for categorization:
    - Analyze the user's message to determine the primary topic or domain
    - Consider programming languages mentioned (python, elixir, javascript, etc.)
    - Consider frameworks or tools mentioned (django, phoenix, react, etc.)
    - Prefer specific subcategories (e.g., "python/django") over general categories (e.g., "python") when applicable
    - If a specific framework is mentioned, use the subcategory format: "language/framework"
    - If only a general language is mentioned, use just the language name
    - Confidence should reflect how certain you are about the categorization
    - If the message doesn't clearly fit any category, set category to null and confidence low
    - For general questions unrelated to any specific category, set category to null

    Examples:
    - "How do I create a Django model?" → {"category": "python/django", "confidence": 0.95}
    - "Python list comprehension syntax?" → {"category": "python", "confidence": 0.9}
    - "What's the weather like?" → {"category": null, "confidence": 0.0}
    - "Phoenix LiveView components" → {"category": "elixir/phoenix", "confidence": 0.95}

    Respond with ONLY the JSON, no other text.
    """
  end

  defp build_categorization_prompt(user_message, categories) do
    # Group categories by parent for better display
    {subcategories, general_categories} =
      Enum.split_with(categories, &String.contains?(&1, "/"))

    categories_text =
      if Enum.empty?(subcategories) do
        """
        Available Categories:
        #{Enum.map(general_categories, &"  - #{&1}") |> Enum.join("\n")}
        """
      else
        # Group subcategories by parent
        grouped =
          subcategories
          |> Enum.group_by(fn cat ->
            cat |> String.split("/") |> List.first()
          end)

        general_text =
          general_categories
          |> Enum.reject(fn cat -> Map.has_key?(grouped, cat) end)
          |> Enum.map(&"  - #{&1}")
          |> Enum.join("\n")

        subcategory_text =
          grouped
          |> Enum.map(fn {parent, subs} ->
            subs_formatted = Enum.map(subs, &"    - #{&1}") |> Enum.join("\n")
            "  - #{parent}\n#{subs_formatted}"
          end)
          |> Enum.join("\n")

        """
        Available Categories:
        #{general_text}
        #{subcategory_text}
        """
      end

    """
    User's Message:
    "#{user_message}"

    #{categories_text}

    Analyze the user's message and select the most specific matching category.
    Prefer subcategories (e.g., "python/django") when the message mentions specific frameworks.
    """
  end

  defp parse_categorization_response(response, categories) do
    # Try to extract JSON from the response
    json_text = extract_json_from_text(response)

    case Jason.decode(json_text) do
      {:ok, parsed} ->
        category = parsed["category"]
        confidence = parsed["confidence"] || 0.0
        reasoning = parsed["reasoning"] || ""

        Logger.info(
          "Orchestrator: Category selected - #{inspect(category)}, Confidence: #{confidence}"
        )

        Logger.debug("Orchestrator: Reasoning: #{reasoning}")

        cond do
          is_nil(category) or category == "" ->
            {:error, :no_match}

          category not in categories ->
            Logger.warning(
              "Orchestrator: Selected category '#{category}' not in available categories"
            )

            # Try to find a partial match (e.g., if LLM returned "python" but we only have "python/django")
            find_fallback_category(category, categories, confidence)

          true ->
            {:ok, category, confidence}
        end

      {:error, reason} ->
        Logger.error("Orchestrator: Failed to parse LLM response as JSON: #{inspect(reason)}")
        Logger.debug("Orchestrator: Response was: #{response}")
        {:error, :invalid_json_response}
    end
  end

  defp find_fallback_category(selected_category, categories, confidence) do
    # If LLM selected "python" but only "python/django" exists, use it with lower confidence
    matching = Enum.filter(categories, &String.starts_with?(&1, selected_category))

    case matching do
      [single_match] ->
        Logger.info("Orchestrator: Using fallback category: #{single_match}")
        {:ok, single_match, confidence * 0.8}

      [] ->
        {:error, :no_match}

      _multiple ->
        # Multiple matches, can't decide
        {:error, :ambiguous_match}
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
