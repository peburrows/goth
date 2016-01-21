use Mix.Config

config :google_auth,
  json: "config/dev-credentials.json" |> Path.expand |> File.read!
