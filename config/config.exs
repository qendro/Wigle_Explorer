# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :wigle_explorer,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :wigle_explorer, WigleExplorerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WigleExplorerWeb.ErrorHTML, json: WigleExplorerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WigleExplorer.PubSub,
  live_view: [signing_salt: "U55nptwb"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  wigle_explorer: [
    args:
      ~w(js/app.js node_modules/maplibre-gl/dist/maplibre-gl-worker.mjs --bundle --format=esm --target=es2022 --outdir=../priv/static/assets/js --entry-names=[name] --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
