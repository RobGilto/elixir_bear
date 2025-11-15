defmodule ElixirBear.Solutions.Solution do
  use Ecto.Schema
  import Ecto.Changeset

  schema "solutions" do
    field :title, :string
    field :user_query, :string
    field :answer_content, :string
    field :metadata, :map
    field :similarity_embedding, :binary

    belongs_to :conversation, ElixirBear.Chat.Conversation
    belongs_to :message, ElixirBear.Chat.Message
    has_many :code_blocks, ElixirBear.Solutions.SolutionCodeBlock
    has_many :tags, ElixirBear.Solutions.SolutionTag

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(solution, attrs) do
    solution
    |> cast(attrs, [:title, :user_query, :answer_content, :metadata, :similarity_embedding, :conversation_id, :message_id])
    |> validate_required([:user_query, :answer_content])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:message_id)
  end
end
