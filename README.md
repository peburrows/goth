![CI](https://github.com/peburrows/goth/workflows/CI/badge.svg)

# Goth

<!-- MDOC !-->

Google + Auth = Goth

A simple library to generate and retrieve OAuth2 tokens for use with Google Cloud Service accounts.

## Installation

**Note:** below are instructions for using Goth v1.3+. For more information on earlier versions of Goth, [see v1.2.0 documentation on hexdocs.pm](https://hexdocs.pm/goth/1.2.0).

1. Add `:goth` to your list of dependencies in `mix.exs`. To use the built-in, Finch-based HTTP
   client adapter, add `:finch` too:

   ```elixir
   def deps do
     [
       {:goth, "~> 1.3-rc"}
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

   ...or use multiple credentials:

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
   iex> Goth.fetch!(MyApp.Goth)
   %Goth.Token{
     expires: 1453356568,
     token: "ya29.cALlJ4ICWRvMkYB-WsAR-CZnExE459PA7QPqKg5nei9y2T9-iqmbcgxq8XrTATNn_BPim",
     type: "Bearer",
     ...
   }
   ```

See `Goth.start_link/1` for more information about possible configuration options.

<!-- MDOC !-->

## Upgrading from Goth 1.2

See [Upgrading from Goth 1.2](UPGRADE_GUIDE.md) guide for more information.

## Community resources

- [How to upload on YouTube Data API with elixir ?](https://mrdotb.com/posts/upload-on-youtube-with-elixir/)
