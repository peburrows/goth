# GoogleAuth

**TODO: Add description**

## Installation

<!-- If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add google_auth to your list of dependencies in `mix.exs`:

        def deps do
          [{:google_auth, "~> 0.0.1"}]
        end

  2. Ensure google_auth is started before your application:

        def application do
          [applications: [:google_auth]]
        end

```elixir
# Here's how I want this to go:

# give GoogleAuth your RSA key
config :google_auth,
  keyfile: "path/to/my/key",
  key: "raw-key-string",
  json: "path/to/google/json/creds.json"

# retrieve an access token (from Google, or from the GenServer)
{:ok, token} = GoogleAuth.get_token(scope: "pubsub")
# do something with that client later
HTTPoison.get(path, [{"Authorization", "Bearer #{token}"}])
``` -->
