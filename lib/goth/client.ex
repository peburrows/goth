defmodule Goth.Client do
  alias Goth.Config
  alias Goth.Token

  @moduledoc """
  `Goth.Client` is the module through which all interaction with Google's APIs flows.
  For the most part, you probably don't want to use this module directly, but instead
  use the other modules that cache and wrap the underlying API calls.

  ## Available Options

  The first parameter is either the token scopes or a tuple of the service
  account client email and its scopes.

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

  def get_access_token(scope), do: get_access_token({:default, scope}, [])

  def get_access_token(scope, opts) when is_binary(scope) and is_list(opts) do
    get_access_token({:default, scope}, opts)
  end

  def get_access_token({account, scope}, opts) when is_binary(scope) and is_list(opts) do
    {:ok, token_source} = Config.get(account, :token_source)
    get_access_token(token_source, {account, scope}, opts)
  end

  @doc false
  def get_access_token(source, info, opts \\ [])
  # Fetch an access token from Google's metadata service for applications running
  # on Google's Cloud platform.
  def get_access_token(type, scope, opts) when is_atom(type) and is_binary(scope) do
    get_access_token(type, {:default, scope}, opts)
  end

  def get_access_token(:metadata, {service_account, scope}, _opts) do
    headers = [{"Metadata-Flavor", "Google"}]
    account = Application.get_env(:goth, :metadata_account, "default")
    metadata = Application.get_env(:goth, :metadata_url, "http://metadata.google.internal")
    endpoint = "computeMetadata/v1/instance/service-accounts"
    url_base = "#{metadata}/#{endpoint}/#{account}"

    url = "#{url_base}/token"
    {:ok, token} = HTTPoison.get(url, headers)
    {:ok, Token.from_response_json({service_account, scope}, token.body)}
  end

  # Fetch an access token from Google's OAuth service using a JWT
  def get_access_token(:oauth_jwt, {account, scope}, opts) do
    %{sub: sub} = destruct_opts(opts)
    endpoint = Application.get_env(:goth, :endpoint, "https://www.googleapis.com")
    url = "#{endpoint}/oauth2/v4/token"

    body =
      {:form,
       [
         grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
         assertion: jwt({account, scope}, opts)
       ]}

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    HTTPoison.post(url, body, headers)
    |> handle_response({account, scope}, sub)
  end

  # Fetch an access token from Google's OAuth service using a refresh token
  def get_access_token(:oauth_refresh, {account, scope}, _opts) do
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
    |> handle_response({account, scope})
  end

  def claims(scope, opts \\ [])
  def claims(scope, iat) when is_integer(iat), do: claims(scope, iat: iat)
  def claims(scope, opts) when is_binary(scope), do: claims({:default, scope}, opts)

  def claims({account, scope}, opts) when is_list(opts) do
    %{iat: iat, sub: sub} = destruct_opts(opts)
    {:ok, email} = Config.get(account, :client_email)

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
  def json(scope, opts) when is_binary(scope), do: json({:default, scope}, opts)

  def json({account, scope}, opts) when is_list(opts) do
    claims({account, scope}, opts)
    |> Jason.encode!()
  end

  def jwt(info, opts \\ [])
  def jwt(scope, iat) when is_integer(iat), do: jwt(scope, iat: iat)
  def jwt(scope, opts) when is_binary(scope), do: jwt({:default, scope}, opts)

  def jwt({account, scope}, opts) when is_list(opts) do
    {:ok, key} = Config.get(account, :private_key)
    signer = Joken.Signer.create("RS256", %{"pem" => key})

    {:ok, jwt} =
      claims({account, scope}, opts)
      |> Joken.Signer.sign(signer)

    jwt
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

  defp handle_response(resp, opts, sub \\ nil)

  defp handle_response({:ok, %{body: body, status_code: code}}, {account, scope}, sub)
       when code in 200..299,
       do: {:ok, Token.from_response_json({account, scope}, sub, body)}

  defp handle_response({:ok, %{body: body}}, _scope, _sub),
    do: {:error, "Could not retrieve token, response: #{body}"}

  defp handle_response(other, _scope, _sub), do: other
end
