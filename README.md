[![Build Status](https://travis-ci.org/peburrows/goth.svg?branch=master)](https://travis-ci.org/peburrows/goth)

# Goth
Google + Auth = Goth

A simple library to generate and retrieve OAuth2 tokens for use with Google Cloud Service accounts.

It can either retrieve tokens using service account credentials or from Google's metadata service for applications running on Google Cloud Platform.

## Installation

1. Add Goth to your list of dependencies in `mix.exs`:
  ```elixir
  def deps do
    [{:goth, "~> 0.4.0"}]
  end
  ```

2. Ensure Goth is started before your application:
  ```elixir
  def application do
    [applications: [:goth]]
  end
  ```

3. Pass in your credentials json downloaded from your GCE account:
  ```elixir
  config :goth,
    json: "path/to/google/json/creds.json" |> File.read!
  ```

  Or, via an ENV var:
  ```elixir
  config :goth, json: {:system, "GCP_CREDENTIALS"}
  ```

You can skip the last step if your application will run on a GCP or GKE instance with appropriate permissions.

If you need to set the email account to impersonate. For example when using service accounts

   ```elixir
   config :goth,
     json: {:system, "GCP_CREDENTIALS"},
     actor_email: "some-email@your-domain.com"
   ```

## Usage

### Retrieve a token:
Call `Token.for_scope/1` passing in a string of scopes, separated by a space:
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
