defmodule ElixirBear.Repo.Migrations.CreateBackgroundImages do
  use Ecto.Migration

  def change do
    create table(:background_images) do
      add :filename, :string, null: false
      add :original_name, :string, null: false
      add :file_path, :string, null: false
      add :is_selected, :boolean, default: false, null: false

      timestamps()
    end

    create index(:background_images, [:is_selected])
  end
end
