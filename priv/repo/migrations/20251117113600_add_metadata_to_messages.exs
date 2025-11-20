defmodule ElixirBear.Repo.Migrations.AddMetadataToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :metadata, :map, default: %{}
    end
  end
end
