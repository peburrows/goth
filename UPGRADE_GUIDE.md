## Upgrading from Goth 1.2

Earlier versions of Goth relied on global application environment configuration which is deprecated
in favour of a more direct and explicit approach in Goth v1.3+. Previously, Goth depended on on
the HTTPoison HTTP client, but now it has an _optional_ dependency on Hackney. Thus, new projects
using Goth and wanting to use Hackney will need to explicitly include it in the dependencies.

Below is a step-by-step upgrade path from Goth 1.x to 1.3:

Change your `mix.exs`:

```elixir
def deps do
  [
    {:goth, "~> 1.3-rc"}
  ]
end
```

You might have code similar to this:

```elixir
# config/config.exs
config :goth,
  json: {:system, "GCP_CREDENTIALS"}
```

```elixir
# lib/myapp.ex
defmodule MyApp do
  def gcloud_authorization() do
    {:ok, token} = Goth.Token.for_scope("https://www.googleapis.com/auth/cloud-platform.read-only")
    "#{token.type} #{token.token}"
  end
end
```

Replace it with:

```elixir
defmodule MyApp.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    credentials = "GCP_CREDENTIALS" |> System.fetch_env!() |> Jason.decode!()
    scopes = ["https://www.googleapis.com/auth/cloud-platform.read-only"]
    source = {:service_account, credentials, scopes: scopes}

    children = [
      {Goth, name: MyApp.Goth, source: source}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

```elixir
# lib/myapp.ex
defmodule MyApp do
  def gcloud_authorization() do
    {:ok, token} = Goth.fetch(MyApp.Goth)
    "#{token.type} #{token.token}"
  end
end
```

For more information on earlier versions of Goth, [see v1.2.0 documentation on hexdocs.pm](https://hexdocs.pm/goth/1.2.0).
