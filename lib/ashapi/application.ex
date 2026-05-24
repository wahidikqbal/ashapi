defmodule Ashapi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AshapiWeb.Telemetry,
      Ashapi.Repo,
      {DNSCluster, query: Application.get_env(:ashapi, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ashapi.PubSub},
      # Start a worker by calling: Ashapi.Worker.start_link(arg)
      # {Ashapi.Worker, arg},
      # Start to serve requests, typically the last entry
      AshapiWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :ashapi]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ashapi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AshapiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
