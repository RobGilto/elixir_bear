defmodule ElixirBear.BackgroundImage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "background_images" do
    field :filename, :string
    field :original_name, :string
    field :file_path, :string
    field :is_selected, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(background_image, attrs) do
    background_image
    |> cast(attrs, [:filename, :original_name, :file_path, :is_selected])
    |> validate_required([:filename, :original_name, :file_path])
  end
end
