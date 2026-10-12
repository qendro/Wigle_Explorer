defmodule WigleExplorer.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: WigleExplorer.PubSub},
      WigleExplorerWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: WigleExplorer.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    WigleExplorerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
