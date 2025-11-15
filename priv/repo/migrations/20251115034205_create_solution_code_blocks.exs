defmodule ElixirBear.Repo.Migrations.CreateSolutionCodeBlocks do
  use Ecto.Migration

  def change do
    create table(:solution_code_blocks) do
      add :solution_id, references(:solutions, on_delete: :delete_all), null: false
      add :code, :text, null: false
      add :language, :string
      add :description, :text
      add :order, :integer, null: false, default: 0

      timestamps()
    end

    create index(:solution_code_blocks, [:solution_id])
    create index(:solution_code_blocks, [:solution_id, :order])
  end
end
