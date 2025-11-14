defmodule ElixirBear.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ElixirBearWeb.Telemetry,
      ElixirBear.Repo,
      {DNSCluster, query: Application.get_env(:elixir_bear, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ElixirBear.PubSub},
      # Registry for conversation workers
      {Registry, keys: :unique, name: ElixirBear.ConversationWorkerRegistry},
      # Dynamic supervisor for conversation workers
      {DynamicSupervisor, strategy: :one_for_one, name: ElixirBear.ConversationWorkerSupervisor},
      # Start to serve requests, typically the last entry
      ElixirBearWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ElixirBear.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ElixirBearWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
