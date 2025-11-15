defmodule ElixirBear.Solutions.SolutionTag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "solution_tags" do
    field :tag_type, :string
    field :tag_value, :string

    belongs_to :solution, ElixirBear.Solutions.Solution

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:solution_id, :tag_type, :tag_value])
    |> validate_required([:solution_id, :tag_type, :tag_value])
    |> foreign_key_constraint(:solution_id)
    |> unique_constraint([:solution_id, :tag_type, :tag_value])
  end
end
