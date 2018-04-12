defmodule Goth.Client do
  alias Goth.Config
  alias Goth.Token

  @moduledoc """
  `Goth.Client` is the module through which all interaction with Google's APIs flows.
  For the most part, you probably don't want to use this module directly, but instead
  use the other modules that cache and wrap the underlying API calls.

  ## Available Options

  Additional token attributes are controlled through options. Available values:

  - `iat` - The time the assertion was issued, default to now.
  - `sub` - The email address of the user for which the application is requesting delegated access.
    Default values is taken from the config `:actor_email`.

  See
  [Google's Documentation](https://developers.google.com/identity/protocols/OAuth2ServiceAccount#authorizingrequests)
  for more details.

  """

  @doc """
  *Note:* Most often, you'll want to use `Goth.Token.for_scope/1` instead of this method.
  As the docs for `Goth.Token.for_scope/1` note, it will return a cached token if one
  already exists, thus saving you the cost of a round-trip to the server to generate a
  new token.

  `Goth.Client.get_access_token/1`, on the other hand will always hit the server to
  retrieve a new token.
  """

  def get_access_token(scope), do: get_access_token(scope, [])

  def get_access_token(scope, opts) when is_binary(scope) and is_list(opts) do
    {:ok, token_source} = Config.get(:token_source)
    get_access_token(token_source, scope, opts)
  end

  @doc false
  def get_access_token(source, scope, opts \\ [])
  # Fetch an access token from Google's metadata service for applications running
  # on Google's Cloud platform.
  def get_access_token(:metadata, scope, _opts) do
    headers = [{"Metadata-Flavor", "Google"}]
    account = Application.get_env(:goth, :metadata_account, "default")
    metadata = Application.get_env(:goth, :metadata_url, "http://metadata.google.internal")
    endpoint = "computeMetadata/v1/instance/service-accounts"
    url_base = "#{metadata}/#{endpoint}/#{account}"

    url = "#{url_base}/token"
    {:ok, token} = HTTPoison.get(url, headers)
    {:ok, Token.from_response_json(scope, token.body)}
  end

  # Fetch an access token from Google's OAuth service using a JWT
  def get_access_token(:oauth_jwt, scope, opts) do
    %{sub: sub} = destruct_opts(opts)
    endpoint = Application.get_env(:goth, :endpoint, "https://www.googleapis.com")
    url = "#{endpoint}/oauth2/v4/token"

    body =
      {:form,
       [grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt(scope, opts)]}

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    HTTPoison.post(url, body, headers)
    |> handle_response(scope)
  end

  # Fetch an access token from Google's OAuth service using a refresh token
  def get_access_token(:oauth_refresh, scope, _opts) do
    {:ok, refresh_token} = Config.get(:refresh_token)
    {:ok, client_id} = Config.get(:client_id)
    {:ok, client_secret} = Config.get(:client_secret)
    endpoint = Application.get_env(:goth, :endpoint, "https://www.googleapis.com")
    url = "#{endpoint}/oauth2/v4/token"

    body =
      {:form,
       [
         grant_type: "refresh_token",
         refresh_token: refresh_token,
         client_id: client_id,
         client_secret: client_secret
       ]}

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    HTTPoison.post(url, body, headers)
    |> handle_response(scope)
  end

  def claims(scope, opts \\ [])
  def claims(scope, iat) when is_integer(iat), do: claims(scope, iat: iat)

  def claims(scope, opts) when is_list(opts) do
    %{iat: iat, sub: sub} = destruct_opts(opts)
    {:ok, email} = Config.get(:client_email)

    c = %{
      "iss" => email,
      "scope" => scope,
      "aud" => "https://www.googleapis.com/oauth2/v4/token",
      "iat" => iat,
      "exp" => iat + 10
    }

    if sub do
      Map.put(c, "sub", sub)
    else
      c
    end
  end

  def json(scope, opts \\ [])
  def json(scope, iat) when is_integer(iat), do: json(scope, iat: iat)

  def json(scope, opts) when is_list(opts) do
    scope
    |> claims(opts)
    |> Poison.encode!()
  end

  def jwt(scope, opts \\ [])
  def jwt(scope, iat) when is_integer(iat), do: jwt(scope, iat: iat)

  def jwt(scope, opts) when is_list(opts) do
    {:ok, key} = Config.get(:private_key)

    scope
    |> claims(opts)
    |> JsonWebToken.sign(%{alg: "RS256", key: JsonWebToken.Algorithm.RsaUtil.private_key(key)})
  end

  @doc "Retrieves the project ID from Google's metadata service"
  def retrieve_metadata_project do
    headers = [{"Metadata-Flavor", "Google"}]
    endpoint = "computeMetadata/v1/project/project-id"
    metadata = Application.get_env(:goth, :metadata_url, "http://metadata.google.internal")
    url = "#{metadata}/#{endpoint}"
    HTTPoison.get!(url, headers).body
  end

  defp destruct_opts(opts) do
    defaults = [
      iat: :os.system_time(:seconds),
      sub:
        case Config.get(:actor_email) do
          {:ok, sub} -> sub
          _ -> nil
        end
    ]

    defaults
    |> Keyword.merge(opts)
    |> Enum.into(%{})
  end

  defp handle_response({:ok, %{body: body, status_code: code}}, scope) when code in 200..299,
    do: {:ok, Token.from_response_json(scope, body)}

  defp handle_response({:ok, %{body: body}}, _scope),
    do: {:error, "Could not retrieve token, response: #{body}"}

  defp handle_response(other, _scope), do: other
end
