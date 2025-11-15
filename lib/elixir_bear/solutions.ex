defmodule ElixirBear.Solutions do
  @moduledoc """
  The Solutions context for managing reusable code solutions.
  """

  import Ecto.Query, warn: false
  alias ElixirBear.Repo

  alias ElixirBear.Solutions.{Solution, SolutionCodeBlock, SolutionTag}

  # Solutions

  @doc """
  Returns the list of solutions.
  """
  def list_solutions do
    Solution
    |> Repo.all()
    |> Repo.preload([:code_blocks, :tags, :conversation, :message])
  end

  @doc """
  Gets a single solution.
  """
  def get_solution!(id) do
    Solution
    |> Repo.get!(id)
    |> Repo.preload([:code_blocks, :tags, :conversation, :message])
  end

  @doc """
  Creates a solution.
  """
  def create_solution(attrs \\ %{}) do
    %Solution{}
    |> Solution.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a solution.
  """
  def update_solution(%Solution{} = solution, attrs) do
    solution
    |> Solution.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a solution.
  """
  def delete_solution(%Solution{} = solution) do
    Repo.delete(solution)
  end

  # Code Blocks

  @doc """
  Creates a code block for a solution.
  """
  def create_code_block(attrs \\ %{}) do
    %SolutionCodeBlock{}
    |> SolutionCodeBlock.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a code block.
  """
  def update_code_block(%SolutionCodeBlock{} = code_block, attrs) do
    code_block
    |> SolutionCodeBlock.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a code block.
  """
  def delete_code_block(%SolutionCodeBlock{} = code_block) do
    Repo.delete(code_block)
  end

  # Tags

  @doc """
  Creates a tag for a solution.
  """
  def create_tag(attrs \\ %{}) do
    %SolutionTag{}
    |> SolutionTag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tag.
  """
  def update_tag(%SolutionTag{} = tag, attrs) do
    tag
    |> SolutionTag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tag.
  """
  def delete_tag(%SolutionTag{} = tag) do
    Repo.delete(tag)
  end

  @doc """
  Searches solutions by tag.
  """
  def search_by_tag(tag_type, tag_value) do
    query =
      from s in Solution,
        join: t in SolutionTag,
        on: t.solution_id == s.id,
        where: t.tag_type == ^tag_type and t.tag_value == ^tag_value,
        preload: [:code_blocks, :tags]

    Repo.all(query)
  end

  @doc """
  Creates a complete solution with code blocks and tags in a single transaction.
  """
  def create_solution_with_associations(solution_attrs, code_blocks_attrs, tags_attrs) do
    Repo.transaction(fn ->
      with {:ok, solution} <- create_solution(solution_attrs),
           {:ok, _code_blocks} <- create_code_blocks_for_solution(solution.id, code_blocks_attrs),
           {:ok, _tags} <- create_tags_for_solution(solution.id, tags_attrs) do
        get_solution!(solution.id)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Private helpers

  defp create_code_blocks_for_solution(solution_id, code_blocks_attrs) do
    code_blocks =
      Enum.with_index(code_blocks_attrs, fn attrs, index ->
        attrs
        |> Map.put(:solution_id, solution_id)
        |> Map.put(:order, Map.get(attrs, :order, index))
        |> then(&create_code_block/1)
      end)

    if Enum.all?(code_blocks, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(code_blocks, fn {:ok, cb} -> cb end)}
    else
      {:error, :code_blocks_creation_failed}
    end
  end

  defp create_tags_for_solution(solution_id, tags_attrs) do
    tags =
      Enum.map(tags_attrs, fn attrs ->
        attrs
        |> Map.put(:solution_id, solution_id)
        |> then(&create_tag/1)
      end)

    if Enum.all?(tags, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(tags, fn {:ok, t} -> t end)}
    else
      {:error, :tags_creation_failed}
    end
  end
end
