use Mix.Config

config :goth,
  json: "config/test-credentials.json" |> Path.expand |> File.read!

# config :bypass, enable_debug_log: true
