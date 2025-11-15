defmodule ElixirBear.Repo.Migrations.AddSolutionRouterSettings do
  use Ecto.Migration

  def change do
    # Add settings for solution router feature
    execute """
    INSERT INTO settings (key, value, inserted_at, updated_at)
    VALUES
      ('enable_solution_router', 'true', datetime('now'), datetime('now')),
      ('solution_router_threshold', '0.75', datetime('now'), datetime('now'))
    ON CONFLICT(key) DO NOTHING;
    """
  end
end
