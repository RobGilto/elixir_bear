defmodule ElixirBear.Repo.Migrations.CreateSolutionTags do
  use Ecto.Migration

  def change do
    create table(:solution_tags) do
      add :solution_id, references(:solutions, on_delete: :delete_all), null: false
      add :tag_type, :string, null: false
      add :tag_value, :string, null: false

      timestamps()
    end

    create index(:solution_tags, [:solution_id])
    create index(:solution_tags, [:tag_type, :tag_value])
    create unique_index(:solution_tags, [:solution_id, :tag_type, :tag_value])
  end
end
