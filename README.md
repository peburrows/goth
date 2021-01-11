![CI](https://github.com/peburrows/goth/workflows/CI/badge.svg)

# Goth

<!-- MDOC !-->

Google + Auth = Goth

A simple library to generate and retrieve OAuth2 tokens for use with Google Cloud Service accounts.

## Installation

1. Add Goth to your list of dependencies in `mix.exs`:

   ```elixir
   def deps do
     [{:goth, "~> 1.3"}]
   end
   ```

2. Add Goth to your supervision tree:

   ```elixir
   defmodule MyApp.Application do
     use Application

     def start(_type, _args) do
       credentials = "GOOGLE_APPLICATION_CREDENTIALS_JSON" |> System.fetch_env!() |> Jason.decode!()

       children = [
         {Goth, name: MyApp.Goth, credentials: credentials}
       ]

       Supervisor.start_link(children, strategy: :one_for_one)
     end
   end
   ```

3. Fetch the token:

    ```elixir
    iex> {:ok, token} = Goth.fetch(MyApp.Goth)
    iex> token
    %Goth.Token{
      expires: 1453356568,
      token: "ya29.cALlJ4ICWRvMkYB-WsAR-CZnExE459PA7QPqKg5nei9y2T9-iqmbcgxq8XrTATNn_BPim",
      type: "Bearer"
    }
    ```

<!-- MDOC !-->

## Upgrading from Goth < 1.3

Earlier versions of Goth relied on global application environment configuration which is deprecated
in favour of a more direct and explicit approach in Goth v1.3+.

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

    children = [
      {Goth, name: MyApp.Goth, credentials: credentials}
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

# TODO

We can close these tickets:

* https://github.com/peburrows/goth/issues/23, https://github.com/peburrows/goth/pull/54 - `:http_opts` option on Goth.start_link/1 and Goth.Token.fetch/1
* https://github.com/peburrows/goth/issues/35
* https://github.com/peburrows/goth/issues/53 - seems a problem with Goth.Config, can be closed as we have new api
* https://github.com/peburrows/goth/issues/57 - we now have a slightly better error message, that the expected shape doesn't match
* https://github.com/peburrows/goth/issues/65 - they can start different Goth instances for different test scenarios. Or use Goth.Token.fetch/1 directly to bypass the cache.
* https://github.com/peburrows/goth/issues/67
* https://github.com/peburrows/goth/issues/69
* https://github.com/peburrows/goth/issues/72 - bug with older Hackney on newer OTP
* https://github.com/peburrows/goth/issues/77, https://github.com/peburrows/goth/pull/79 - do we want to support this, or users would explicitly load from GOOGLE_APPLICATION_CREDENTIALS env or ~/.config/gcloud/application_default_credentials.json in their supervision tree?
* https://github.com/peburrows/goth/pull/66 - `:refresh_before` option on `Goth.start_link/1`.
* https://github.com/peburrows/goth/pull/76
* https://github.com/peburrows/goth/pull/80
