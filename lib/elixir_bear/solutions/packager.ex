defmodule ElixirBear.Solutions.Packager do
  @moduledoc """
  Packages conversation messages into solution structures for storage.
  """

  alias ElixirBear.Solutions.MarkdownParser
  alias ElixirBear.Chat

  @doc """
  Packages a conversation message pair (user + assistant) into a solution structure.

  Takes:
  - user_message_id: The ID of the user's question message
  - assistant_message_id: The ID of the assistant's response message

  Returns a map with:
  - :solution_attrs - Attributes for creating the solution
  - :code_blocks_attrs - List of attributes for creating code blocks
  - :metadata - Programmatically extracted metadata
  - :needs_llm_processing - Boolean indicating if LLM metadata extraction is needed

  ## Example

      iex> Packager.package_from_messages(user_msg_id, assistant_msg_id)
      %{
        solution_attrs: %{
          user_query: "How do I use pattern matching?",
          answer_content: "Pattern matching in Elixir...",
          conversation_id: 1,
          message_id: 2
        },
        code_blocks_attrs: [
          %{code: "def hello(name), do: ...", language: "elixir", order: 0}
        ],
        metadata: %{has_code_blocks: true, languages: ["elixir"]},
        needs_llm_processing: true
      }
  """
  def package_from_messages(user_message_id, assistant_message_id) do
    user_message = Chat.get_message!(user_message_id)
    assistant_message = Chat.get_message!(assistant_message_id)

    package_from_message_structs(user_message, assistant_message)
  end

  @doc """
  Packages message structs directly into a solution structure.
  """
  def package_from_message_structs(user_message, assistant_message) do
    code_blocks = MarkdownParser.extract_code_blocks(assistant_message.content)
    metadata = MarkdownParser.extract_metadata(assistant_message.content)

    solution_attrs = %{
      user_query: user_message.content,
      answer_content: assistant_message.content,
      conversation_id: assistant_message.conversation_id,
      message_id: assistant_message.id,
      metadata: %{
        extracted_at: DateTime.utc_now(),
        code_block_count: metadata.code_block_count,
        languages: metadata.languages
      }
    }

    code_blocks_attrs =
      Enum.map(code_blocks, fn block ->
        %{
          code: block.code,
          language: block.language,
          order: block.order
        }
      end)

    %{
      solution_attrs: solution_attrs,
      code_blocks_attrs: code_blocks_attrs,
      metadata: metadata,
      needs_llm_processing: true
    }
  end

  @doc """
  Validates that a message pair is suitable for solution extraction.

  Returns {:ok, package} or {:error, reason}
  """
  def validate_and_package(user_message_id, assistant_message_id) do
    try do
      package = package_from_messages(user_message_id, assistant_message_id)

      cond do
        !package.metadata.has_code_blocks ->
          {:error, :no_code_blocks}

        String.length(package.solution_attrs.user_query) < 3 ->
          {:error, :query_too_short}

        String.length(package.solution_attrs.answer_content) < 10 ->
          {:error, :answer_too_short}

        true ->
          {:ok, package}
      end
    rescue
      Ecto.NoResultsError -> {:error, :message_not_found}
      e -> {:error, {:unexpected_error, e}}
    end
  end

  @doc """
  Merges LLM-generated metadata into a solution package.

  Takes a package and LLM-generated metadata (title, topics, difficulty, description)
  and merges them into the solution attributes.
  """
  def merge_llm_metadata(package, llm_metadata) do
    updated_solution_attrs =
      package.solution_attrs
      |> Map.put(:title, llm_metadata[:title])
      |> Map.update!(:metadata, fn meta ->
        Map.merge(meta, %{
          topics: llm_metadata[:topics] || [],
          difficulty: llm_metadata[:difficulty],
          description: llm_metadata[:description],
          llm_processed_at: DateTime.utc_now()
        })
      end)

    # Update code block descriptions if provided
    updated_code_blocks_attrs =
      if llm_metadata[:code_block_descriptions] do
        Enum.zip(package.code_blocks_attrs, llm_metadata.code_block_descriptions)
        |> Enum.map(fn {block, description} ->
          Map.put(block, :description, description)
        end)
      else
        package.code_blocks_attrs
      end

    # Create tags from topics and difficulty
    tags_attrs = create_tags_from_metadata(llm_metadata)

    %{
      solution_attrs: updated_solution_attrs,
      code_blocks_attrs: updated_code_blocks_attrs,
      tags_attrs: tags_attrs,
      metadata: package.metadata
    }
  end

  # Private helpers

  defp create_tags_from_metadata(llm_metadata) do
    topic_tags =
      (llm_metadata[:topics] || [])
      |> Enum.map(fn topic ->
        %{tag_type: "topic", tag_value: topic}
      end)

    difficulty_tags =
      if llm_metadata[:difficulty] do
        [%{tag_type: "difficulty", tag_value: llm_metadata[:difficulty]}]
      else
        []
      end

    language_tags =
      (llm_metadata[:languages] || [])
      |> Enum.map(fn lang ->
        %{tag_type: "language", tag_value: lang}
      end)

    topic_tags ++ difficulty_tags ++ language_tags
  end
end
