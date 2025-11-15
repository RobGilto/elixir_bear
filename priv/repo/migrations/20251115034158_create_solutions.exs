defmodule ElixirBear.Repo.Migrations.CreateSolutions do
  use Ecto.Migration

  def change do
    create table(:solutions) do
      add :title, :string
      add :user_query, :text, null: false
      add :answer_content, :text, null: false
      add :conversation_id, references(:conversations, on_delete: :nilify_all)
      add :message_id, references(:messages, on_delete: :nilify_all)
      add :metadata, :map, default: %{}
      add :similarity_embedding, :binary

      timestamps()
    end

    create index(:solutions, [:conversation_id])
    create index(:solutions, [:message_id])
  end
end
