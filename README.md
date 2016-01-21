# GoogleAuth

**TODO: Add description**

## Installation

1. Add google_auth to your list of dependencies in `mix.exs`:
  ```elixir
  def deps do
    [{:google_auth, "~> 0.0.1"}]
  end
  ```

2. Ensure google_auth is started before your application:
  ```elixir
  def application do
    [applications: [:google_auth]]
  end
  ```

3. Pass in your credentials json downloaded from your GCE account:
  ```elixir
  config :google_auth,
    json: "path/to/google/json/creds.json" |> File.read!
  ```

## Usage

### Retrieve a token:
Call `Token.for_scope/1` passing in a string of scopes, separated by a comma:
```elixir
alias GoogleAuth.Token
{:ok, token} = Token.for_scope("https://www.googleapis.com/auth/pubsub")
#=>
  %GoogleAuth.Token{
    expires: 1453356568,
    token: "ya29.cALlJ4ICWRvMkYB-WsAR-CZnExE459PA7QPqKg5nei9y2T9-iqmbcgxq8XrTATNn_BPim",
    type: "Bearer"
  }
```
