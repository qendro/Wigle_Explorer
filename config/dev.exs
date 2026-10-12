import Config

config :wigle_explorer, WigleExplorerWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "WFQeTnVFRAc+Cy9k6RveP2uxZ+7KKLrqQGQiY2xU1LS8F3tkPj9vZ3o3Vc9elgXO",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:wigle_explorer, ~w(--sourcemap=inline --watch)]}
  ]

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, enable_expensive_runtime_checks: true
