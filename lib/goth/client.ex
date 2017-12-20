defmodule Goth.Client do
  alias Goth.Config
  alias Goth.Token

  @moduledoc """
  `Goth.Client` is the module through which all interaction with Google's APIs flows.
  For the most part, you probably don't want to use this module directly, but instead
  use the other modules that cache and wrap the underlying API calls.
  """

  @doc """
  *Note:* Most often, you'll want to use `Goth.Token.for_scope/1` instead of this method.
  As the docs for `Goth.Token.for_scope/1` note, it will return a cached token if one
  already exists, thus saving you the cost of a round-trip to the server to generate a
  new token.

  `Goth.Client.get_access_token/1`, on the other hand will always hit the server to
  retrieve a new token.
  """

  def get_access_token(scope) do
    {:ok, token_source} = Config.get(:token_source)
    get_access_token(token_source, scope)
  end

  # Fetch an access token from Google's metadata service for applications running
  # on Google's Cloud platform.
  def get_access_token(:metadata, scope) do
    headers  = [{"Metadata-Flavor", "Google"}]
    account  = Application.get_env(:goth, :metadata_account, "default")
    metadata = Application.get_env(:goth, :metadata_url,
                                   "http://metadata.google.internal")
    endpoint = "computeMetadata/v1/instance/service-accounts"
    url_base = "#{metadata}/#{endpoint}/#{account}"

    url      = "#{url_base}/token"
    {:ok, token} = HTTPoison.get(url, headers)
    {:ok, Token.from_response_json(scope, token.body)}
  end

  # Fetch an access token from Google's OAuth service using a JWT
  def get_access_token(:oauth_jwt, scope) do
    endpoint = Application.get_env(:goth, :endpoint, "https://www.googleapis.com")
    url      = "#{endpoint}/oauth2/v4/token"
    body     = {:form, [grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
                        assertion:  jwt(scope)]}
    headers  = [{"Content-Type", "application/x-www-form-urlencoded"}]

    {:ok, response} = HTTPoison.post(url, body, headers)
    if response.status_code >= 200 && response.status_code < 300 do
      {:ok, Token.from_response_json(scope, response.body)}
    else
      {:error, "Could not retrieve token, response: #{response.body}"}
    end
  end

  # Fetch an access token from Google's OAuth service using a refresh token
  def get_access_token(:oauth_refresh, scope) do
    {:ok, refresh_token} = Config.get(:refresh_token)
    {:ok, client_id} = Config.get(:client_id)
    {:ok, client_secret} = Config.get(:client_secret)
    endpoint = Application.get_env(:goth, :endpoint, "https://www.googleapis.com")
    url      = "#{endpoint}/oauth2/v4/token"
    body     = {:form, [grant_type: "refresh_token",
                        refresh_token: refresh_token,
                        client_id: client_id,
                        client_secret: client_secret]}
    headers  = [{"Content-Type", "application/x-www-form-urlencoded"}]

    {:ok, response} = HTTPoison.post(url, body, headers)
    if response.status_code >= 200 && response.status_code < 300 do
      {:ok, Token.from_response_json(scope, response.body)}
    else
      {:error, "Could not retrieve token, response: #{response.body}"}
    end
  end

  def claims(scope), do: claims(scope, :os.system_time(:seconds))
  def claims(scope, iat) do
    {:ok, email} = Config.get(:client_email)
    c =
      %{
        "iss"   => email,
        "scope" => scope,
        "aud"   => "https://www.googleapis.com/oauth2/v4/token",
        "iat"   => iat,
        "exp"   => iat+10
      }
    case Config.get(:actor_email) do
      {:ok, sub} -> Map.put(c, "sub", sub)
      _ -> c
    end
  end

  def json(scope), do: json(scope, :os.system_time(:seconds))
  def json(scope, iat) do
    scope
    |> claims(iat)
    |> Poison.encode!
  end

  def jwt(scope), do: jwt(scope, :os.system_time(:seconds))
  def jwt(scope, iat) do
    {:ok, key} = Config.get(:private_key)
    scope
    |> claims(iat)
    |> JsonWebToken.sign(%{alg: "RS256", key: JsonWebToken.Algorithm.RsaUtil.private_key(key)})
  end

  @doc "Retrieves the project ID from Google's metadata service"
  def retrieve_metadata_project do
    headers  = [{"Metadata-Flavor", "Google"}]
    endpoint = "computeMetadata/v1/project/project-id"
    metadata = Application.get_env(:goth, :metadata_url,
      "http://metadata.google.internal")
    url      = "#{metadata}/#{endpoint}"
    HTTPoison.get!(url, headers).body
  end
end
