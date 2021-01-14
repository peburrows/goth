# Goth
Google + Auth = Goth

A simple library to generate and retrieve OAuth2 tokens for use with Google Cloud Service accounts.

It can either retrieve tokens using service account credentials or from Google's metadata service for applications running on Google Cloud Platform.

## Installation

1. Add Goth to your list of dependencies in `mix.exs`:
  ```elixir
  def deps do
    [{:goth, "~> 1.2.0"}]
  end
  ```

2. Pass in your credentials json downloaded from your GCE account:

  ```elixir
  config :goth,
    json: "path/to/google/json/creds.json" |> File.read!
  ```

  Or, via an ENV var:
  ```elixir
  config :goth, json: {:system, "GCP_CREDENTIALS"}
  ```

  Or, via your own config module:
  ```elixir
  config :goth, config_module: MyConfigMod
  ```
  ```elixir
  defmodule MyConfigMod do
    use Goth.Config

    def init(config) do
      {:ok, Keyword.put(config, :json, System.get_env("MY_GCP_JSON_CREDENTIALS"))}
    end
  end
  ```

You can also use a JSON file containing an array of service accounts to be able to use different identities in your application. Each service
account will be identified by its ```client_email```, which can be passed to ```Goth.Token.for_scope/1``` to specify which service account to use.

For example, if your JSON file contains the following:

```json
[
  {
    "client_email": "account1@myproject.iam.gserviceaccount.com",
    ...
  },
  {
    "client_email": "account2@myproject.iam.gserviceaccount.com",
    ...
  }
]
```

You can use the following to get a token for the second service account:

```elixir
def get_token do
  {:ok, token} = Goth.Token.for_scope({
    "account2@myproject.iam.gserviceaccount.com",
    "https://www.googleapis.com/auth/cloud-platform.read-only"})
end
```

You can skip the last step if your application will run on a GCP or GKE instance with appropriate permissions.

If you need to set the email account to impersonate. For example when using service accounts

  ```elixir
  config :goth,
    json: {:system, "GCP_CREDENTIALS"},
    actor_email: "some-email@your-domain.com"
  ```

Alternatively, you can pass your sub email on a per-call basis, for example:

  ```elixir
  Goth.Token.for_scope("https://www.googleapis.com/auth/pubsub",
                       "some-email@your-domain.com")
  ```

If you need to disable Goth in certain environments, you can set a `disabled`
flag in your config:

  ```elixir
  config :goth,
    disabled: true
  ```

This initializes Goth with an empty config, so any attempts to actually generate
tokens will fail.

## Usage

### Retrieve a token:
Call `Token.for_scope/1` passing in a string of [scopes](https://developers.google.com/identity/protocols/googlescopes), separated by a space:
```elixir
alias Goth.Token
{:ok, token} = Token.for_scope("https://www.googleapis.com/auth/pubsub")
#=>
  %Goth.Token{
    expires: 1453356568,
    token: "ya29.cALlJ4ICWRvMkYB-WsAR-CZnExE459PA7QPqKg5nei9y2T9-iqmbcgxq8XrTATNn_BPim",
    type: "Bearer"
  }
```
