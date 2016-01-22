# Goth
Google + Auth = Goth

A simple library to generate and retrieve Oauth2 tokens for use with Google Cloud Service accounts.

## Installation

1. Add Goth to your list of dependencies in `mix.exs`:
  ```elixir
  def deps do
    [{:goth, "~> 0.0.1"}]
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

## Usage

### Retrieve a token:
Call `Token.for_scope/1` passing in a string of scopes, separated by a comma:
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
