defmodule ElixirBear.Solutions.SolutionCodeBlock do
  use Ecto.Schema
  import Ecto.Changeset

  schema "solution_code_blocks" do
    field :code, :string
    field :language, :string
    field :description, :string
    field :order, :integer

    belongs_to :solution, ElixirBear.Solutions.Solution

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(code_block, attrs) do
    code_block
    |> cast(attrs, [:solution_id, :code, :language, :description, :order])
    |> validate_required([:solution_id, :code, :order])
    |> foreign_key_constraint(:solution_id)
  end
end
