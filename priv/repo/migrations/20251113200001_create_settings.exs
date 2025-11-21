defmodule ElixirBear.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings) do
      add :key, :string, null: false
      add :value, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:key])

    # Insert default settings
    execute """
            INSERT INTO settings (key, value, inserted_at, updated_at)
            VALUES
              ('openai_api_key', '', datetime('now'), datetime('now')),
              ('system_prompt', '', datetime('now'), datetime('now'))
            """,
            """
            DELETE FROM settings WHERE key IN ('openai_api_key', 'system_prompt')
            """
  end
end
