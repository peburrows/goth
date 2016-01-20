use Mix.Config

config :google_auth,
  json: "config/test-credentials.json" |> Path.expand |> File.read!
