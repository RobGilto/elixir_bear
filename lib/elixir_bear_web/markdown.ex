defmodule ElixirBearWeb.Markdown do
  @moduledoc """
  Processes markdown text with syntax highlighting for code blocks.
  """

  @doc """
  Converts markdown to HTML with syntax highlighted code blocks.
  Returns a Phoenix.HTML.safe string.

  Options:
  - `:message_id` - The ID of the message containing this markdown (for edit persistence)
  """
  def to_html(markdown, opts \\ [])

  def to_html(markdown, opts) when is_binary(markdown) do
    message_id = Keyword.get(opts, :message_id)

    markdown
    |> Earmark.as_html!()
    |> process_html_code_blocks(message_id)
    |> Phoenix.HTML.raw()
  end

  def to_html(nil, _opts), do: Phoenix.HTML.raw("")

  # Process HTML code blocks to add syntax highlighting and copy button
  defp process_html_code_blocks(html, message_id) do
    # Match code blocks with optional language class
    # Use [\s\S] to match any character including newlines
    regex = ~r/<pre><code(?:\s+class="([^"]+)")?>([\s\S]*?)<\/code><\/pre>/

    Regex.replace(regex, html, fn _match, lang, code ->
      # Decode HTML entities in code
      decoded_code =
        code
        |> String.replace("&lt;", "<")
        |> String.replace("&gt;", ">")
        |> String.replace("&amp;", "&")
        |> String.replace("&quot;", "\"")
        |> String.replace("&#39;", "'")

      highlighted = highlight_code(decoded_code, lang)

      # Escape the code for the data attribute
      escaped_for_attr =
        decoded_code
        |> String.replace("&", "&amp;")
        |> String.replace("\"", "&quot;")
        |> String.replace("<", "&lt;")
        |> String.replace(">", "&gt;")

      message_data = if message_id, do: ~s( data-message-id="#{message_id}"), else: ""

      """
      <pre#{message_data}>
        <code class="highlight language-#{lang}">#{highlighted}</code>
        <textarea class="code-editor">#{escaped_for_attr}</textarea>
        <div class="code-controls">
          <button class="code-button reveal-button">Reveal</button>
          <button class="code-button edit-button">Edit</button>
          <button class="code-button copy-button" data-clipboard-text="#{escaped_for_attr}">Copy</button>
        </div>
      </pre>
      """
    end)
  end

  # Highlight code based on language
  defp highlight_code(code, lang) when lang in ["elixir", "ex", "exs"] do
    Makeup.highlight_inner_html(code, lexer: Makeup.Lexers.ElixirLexer)
  rescue
    _ -> escape_html(code)
  end

  defp highlight_code(code, _lang) do
    # For other languages, just escape HTML for now
    # You can add more Makeup lexers here (makeup_erlang, makeup_js, etc.)
    escape_html(code)
  end

  # Escape HTML entities
  defp escape_html(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
