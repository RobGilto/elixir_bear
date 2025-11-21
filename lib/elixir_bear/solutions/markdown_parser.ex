defmodule ElixirBear.Solutions.MarkdownParser do
  @moduledoc """
  Parses markdown content to extract code blocks and their metadata.
  """

  @doc """
  Extracts code blocks from markdown content.

  Returns a list of maps with:
  - :code - The code content
  - :language - The language identifier (e.g., "elixir", "javascript")
  - :order - The position in the document (0-indexed)

  ## Examples

      iex> content = \"\"\"
      ...> Some text
      ...> ```elixir
      ...> def hello, do: "world"
      ...> ```
      ...> More text
      ...> ```javascript
      ...> console.log("hello");
      ...> ```
      ...> \"\"\"
      iex> MarkdownParser.extract_code_blocks(content)
      [
        %{code: "def hello, do: \\"world\\"", language: "elixir", order: 0},
        %{code: "console.log(\\"hello\\");", language: "javascript", order: 1}
      ]
  """
  def extract_code_blocks(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> parse_lines([])
    |> Enum.reverse()
    |> Enum.with_index(fn block, index -> Map.put(block, :order, index) end)
  end

  def extract_code_blocks(_), do: []

  # Private parsing functions

  defp parse_lines([], acc), do: acc

  defp parse_lines([line | rest], acc) do
    case detect_code_fence(line) do
      {:open, language} ->
        {code_lines, remaining} = collect_code_block(rest, [])
        code = Enum.join(code_lines, "\n")
        block = %{code: code, language: language}
        parse_lines(remaining, [block | acc])

      :none ->
        parse_lines(rest, acc)
    end
  end

  defp detect_code_fence(line) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, "```") ->
        language =
          trimmed
          |> String.trim_leading("```")
          |> String.trim()
          |> case do
            "" -> nil
            lang -> lang
          end

        {:open, language}

      true ->
        :none
    end
  end

  defp collect_code_block([], acc), do: {Enum.reverse(acc), []}

  defp collect_code_block([line | rest], acc) do
    if String.trim_leading(line) |> String.starts_with?("```") do
      # Found closing fence
      {Enum.reverse(acc), rest}
    else
      # Continue collecting code
      collect_code_block(rest, [line | acc])
    end
  end

  @doc """
  Extracts metadata from content that might be useful for LLM analysis.

  Returns a map with:
  - :has_code_blocks - Boolean indicating if code blocks were found
  - :code_block_count - Number of code blocks
  - :languages - List of unique languages used
  - :content_length - Character length of the content
  """
  def extract_metadata(content) when is_binary(content) do
    code_blocks = extract_code_blocks(content)
    languages = code_blocks |> Enum.map(& &1.language) |> Enum.uniq() |> Enum.reject(&is_nil/1)

    %{
      has_code_blocks: length(code_blocks) > 0,
      code_block_count: length(code_blocks),
      languages: languages,
      content_length: String.length(content)
    }
  end

  def extract_metadata(_),
    do: %{
      has_code_blocks: false,
      code_block_count: 0,
      languages: [],
      content_length: 0
    }
end
