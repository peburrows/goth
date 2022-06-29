![CI](https://github.com/peburrows/goth/workflows/CI/badge.svg)

# Goth

<!-- MDOC !-->

Google + Auth = Goth

A simple library to generate and retrieve OAuth2 tokens for use with Google Cloud Service accounts.

## Installation

**Note:** below are instructions for using Goth v1.3+. For more information on earlier versions of Goth, [see v1.2.0 documentation on hexdocs.pm](https://hexdocs.pm/goth/1.2.0).

1. Add `:goth` to your list of dependencies in `mix.exs`.

   ```elixir
   def deps do
     [
       {:goth, "~> 1.3"}
     ]
   end
   ```

2. Add Goth to your supervision tree:

   ```elixir
   defmodule MyApp.Application do
     use Application

     def start(_type, _args) do
       credentials = "GOOGLE_APPLICATION_CREDENTIALS_JSON" |> System.fetch_env!() |> Jason.decode!()
       source = {:service_account, credentials}

       children = [
         {Goth, name: MyApp.Goth, source: source}
       ]

       Supervisor.start_link(children, strategy: :one_for_one)
     end
   end
   ```

   If you set `GOOGLE_APPLICATION_CREDENTIALS` or `GOOGLE_APPLICATION_CREDENTIALS_JSON`, have a
   `~/.config/gcloud/application_default_credentials.json` file, or deploy your application to
   Google Cloud, you can omit the `:source` option:

   ```elixir
   def start(_type, _args) do
     children = [
       {Goth, name: MyApp.Goth}
     ]

     Supervisor.start_link(children, strategy: :one_for_one)
   end
   ```

   If you want to use multiple credentials, you may consider doing:

   ```elixir
   def start(_type, _args) do
     Supervisor.start_link(servers(), strategy: :one_for_one)
   end

   defp servers do
     servers = [
       {MyApp.Cred1, source1},
       ...
       {MyApp.CredN, source2}
     ]

     for {name, source} <- servers do
       Supervisor.child_spec({Goth, name: name, source: source}, id: name)
     end
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
