![CI](https://github.com/peburrows/goth/workflows/CI/badge.svg)

# Goth

<!-- MDOC !-->

Google + Auth = Goth

A simple library to generate and retrieve OAuth2 tokens for use with Google Cloud Service accounts.

## Installation

**Note:** below are instructions for using the upcoming v1.3.0 version. For more information on earlier versions of Goth, [see v1.2.0 documentation on hexdocs.pm](https://hexdocs.pm/goth/1.2.0).

1. Add Goth to your list of dependencies in `mix.exs`:

   ```elixir
   def deps do
     [{:goth, github: "peburrows/goth"}]
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

## Google Compute Metadata

Every compute instance stores its metadata on a metadata server.
Goth can query this metadata server to fetch authentication credentials
for a service account within the instance.

The following services support compute instance metadata:

  * [Google Compute Engine](https://cloud.google.com/compute/docs/metadata/default-metadata-values#vm_instance_metadata) / Google Kubernetes Engine
  * [App Engine](https://cloud.google.com/appengine/docs/standard/java/accessing-instance-metadata#identifying_which_metadata_endpoint_to_use)
  * [Cloud Run](https://cloud.google.com/run/docs/securing/service-identity#access_tokens)

To query the metadata server for an access token, use a tuple
of `{:instance, account}` with the name of the service account:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Goth, name: MyApp.Goth, credentials: {:instance, "default"}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**A note about instance metadata and scope:**

Most of the time instance credentials do not require a scope
to request an access token. In fact, scope is only available
to be set for [service identity access tokens](https://cloud.google.com/run/docs/securing/service-identity#access_tokens)
on App Engine and Cloud Run.

Therefore when using instance credentials, `scope` must be
passed explicitly:

```elixir
Goth.Token.fetch(%{
  credentials: {:instance, "12345-user@iam.example.com"},
  scope: "https://www.googleapis.com/auth/pubsub"
})
```

Consult the full list of [Google OAuth scopes](https://developers.google.com/identity/protocols/googlescopes)
to find which scopes you need.



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
