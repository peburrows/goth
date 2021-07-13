![CI](https://github.com/peburrows/goth/workflows/CI/badge.svg)

# Goth

<!-- MDOC !-->

Google + Auth = Goth

A simple library to generate and retrieve OAuth2 tokens for use with Google Cloud Service accounts.

## Installation

**Note:** below are instructions for using Goth v1.3+. For more information on earlier versions of Goth, [see v1.2.0 documentation on hexdocs.pm](https://hexdocs.pm/goth/1.2.0).

1. Add `:goth` to your list of dependencies in `mix.exs`. To use the built-in, Hackney-based HTTP
   client adapter, add `:hackney` too:

   ```elixir
   def deps do
     [
       {:goth, "~> 1.3-rc"},
       {:hackney, "~> 1.17"}
     ]
   end
   ```

2. Add Goth to your supervision tree:

   ```elixir
   defmodule MyApp.Application do
     use Application

     def start(_type, _args) do
       credentials = "GOOGLE_APPLICATION_CREDENTIALS_JSON" |> System.fetch_env!() |> Jason.decode!()
       source = {:service_account, credentials, []}

       children = [
         {Goth, name: MyApp.Goth, source: source}
       ]

       Supervisor.start_link(children, strategy: :one_for_one)
     end
   end
   ```

2.1. ...or use multiple credentials

   ```elixir
   defmodule MyApp.Application do
     use Application

     def start(_type, _args) do
       Supervisor.start_link(load_credentials(), strategy: :one_for_one)
     end

     defp load_credentials do
       [
         {MyApp.Cred1, "CREDENTIALS_JSON_1"},
         ...
         {MyApp.CredN, "CREDENTIALS_JSON_N"}
       ]
       |> Enum.map(fn {id, env_var} ->
         credentials = env_var |> System.fetch_env!() |> Jason.decode!()
         source = {:service_account, credentials, []}
         Supervisor.child_spec({Goth, name: id, source: source}, id: id)
       end)
   end
   ```

3. Fetch the token:

    ```elixir
    iex> {:ok, token} = Goth.fetch(MyApp.Goth)
    iex> token
    %Goth.Token{
      expires: 1453356568,
      token: "ya29.cALlJ4ICWRvMkYB-WsAR-CZnExE459PA7QPqKg5nei9y2T9-iqmbcgxq8XrTATNn_BPim",
      type: "Bearer",
      ...
    }
    ```

See `Goth.start_link/1` for more information about possible configuration options.

<!-- MDOC !-->

## Upgrading from Goth < 1.3

Earlier versions of Goth relied on global application environment configuration which is deprecated
in favour of a more direct and explicit approach in Goth v1.3+. Previously, we were depending
on the HTTPoison HTTP client, now we have an _optional_ dependency on Hackney, so in order
to use it, you need to explicitly include it in your dependencies too:

Change your `mix.exs`:

```elixir
def deps do
 [
   {:goth, "~> 1.3-rc"},
   {:hackney, "~> 1.17"}
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
