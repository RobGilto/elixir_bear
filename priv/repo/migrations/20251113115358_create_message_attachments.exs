defmodule ElixirBear.Repo.Migrations.CreateMessageAttachments do
  use Ecto.Migration

  def change do
    create table(:message_attachments) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :file_type, :string, null: false  # "image", "audio", or "text"
      add :file_path, :string, null: false
      add :original_name, :string, null: false
      add :mime_type, :string, null: false
      add :file_size, :integer
      add :metadata, :map  # For storing width/height, duration, etc.

      timestamps()
    end

    create index(:message_attachments, [:message_id])
  end
end
