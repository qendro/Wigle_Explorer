import Config

if config_env() != :test do
  config :wigle_explorer,
    wigle_credentials: {System.get_env("WIGLE_API_NAME"), System.get_env("WIGLE_API_TOKEN")}
end

config :wigle_explorer,
  map_style_url: System.get_env("MAP_STYLE_URL", "https://tiles.openfreemap.org/styles/positron")

if System.get_env("PHX_SERVER") do
  config :wigle_explorer, WigleExplorerWeb.Endpoint, server: true
end

config :wigle_explorer, WigleExplorerWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  config :wigle_explorer, WigleExplorerWeb.Endpoint,
    live_reload: [
      patterns: [
        ~r"priv/static/.*\.(js|css|png|jpeg|jpg|gif|svg)$",
        ~r"lib/wigle_explorer_web/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  config :wigle_explorer, WigleExplorerWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST", "localhost"), port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
