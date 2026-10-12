defmodule WigleExplorerWeb.Router do
  use WigleExplorerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WigleExplorerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", WigleExplorerWeb do
    pipe_through :browser

    live "/", ExplorerLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", WigleExplorerWeb do
  #   pipe_through :api
  # end
end
