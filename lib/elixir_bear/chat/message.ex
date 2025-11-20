defmodule ElixirBear.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :conversation, ElixirBear.Chat.Conversation
    has_many :attachments, ElixirBear.Chat.MessageAttachment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content, :metadata])
    |> validate_required([:conversation_id, :role, :content])
    |> validate_inclusion(:role, ["system", "user", "assistant"])
    |> foreign_key_constraint(:conversation_id)
  end
end
