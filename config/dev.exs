use Mix.Config

try do
  config :goth,
    json: "config/dev-credentials.json" |> Path.expand |> File.read!
rescue
  _ -> :ok
end
