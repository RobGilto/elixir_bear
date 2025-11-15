defmodule ElixirBear.Repo.Migrations.AddSolutionExtractionSettings do
  use Ecto.Migration

  def change do
    # Add settings for solution extraction LLM
    execute """
    INSERT INTO settings (key, value, inserted_at, updated_at)
    VALUES
      ('solution_extraction_provider', 'ollama', datetime('now'), datetime('now')),
      ('solution_extraction_ollama_model', 'llama3.2', datetime('now'), datetime('now')),
      ('solution_extraction_openai_model', 'gpt-4o-mini', datetime('now'), datetime('now'))
    ON CONFLICT(key) DO NOTHING;
    """
  end
end
