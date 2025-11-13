defmodule ElixirBear.Repo.Migrations.AddOllamaSettings do
  use Ecto.Migration

  def up do
    # Add Ollama-related settings to the settings table
    execute """
    INSERT INTO settings (key, value, inserted_at, updated_at) VALUES
    ('llm_provider', 'openai', datetime('now'), datetime('now')),
    ('ollama_model', 'llama3.2', datetime('now'), datetime('now')),
    ('ollama_url', 'http://localhost:11434', datetime('now'), datetime('now'))
    """
  end

  def down do
    # Remove Ollama settings
    execute "DELETE FROM settings WHERE key IN ('llm_provider', 'ollama_model', 'ollama_url')"
  end
end
