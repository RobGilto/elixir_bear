defmodule ElixirBear.Repo.Migrations.AddOrchestratorSettings do
  use Ecto.Migration

  def change do
    # Insert default orchestrator settings
    execute """
    INSERT INTO settings (key, value, inserted_at, updated_at)
    VALUES
      ('enable_prompt_orchestrator', 'false', datetime('now'), datetime('now')),
      ('orchestrator_prompts', '{}', datetime('now'), datetime('now'))
    """, """
    DELETE FROM settings WHERE key IN ('enable_prompt_orchestrator', 'orchestrator_prompts')
    """
  end
end
