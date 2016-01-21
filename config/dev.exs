use Mix.Config

config :goth,
  json: "config/dev-credentials.json" |> Path.expand |> File.read!
