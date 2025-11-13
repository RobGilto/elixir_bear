defmodule ElixirBear.Chat.MessageAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  alias ElixirBear.Chat.Message

  schema "message_attachments" do
    field :file_type, :string
    field :file_path, :string
    field :original_name, :string
    field :mime_type, :string
    field :file_size, :integer
    field :metadata, :map

    belongs_to :message, Message

    timestamps()
  end

  @doc false
  def changeset(message_attachment, attrs) do
    message_attachment
    |> cast(attrs, [:message_id, :file_type, :file_path, :original_name, :mime_type, :file_size, :metadata])
    |> validate_required([:message_id, :file_type, :file_path, :original_name, :mime_type])
    |> validate_inclusion(:file_type, ["image", "audio", "text"])
    |> foreign_key_constraint(:message_id)
  end
end
