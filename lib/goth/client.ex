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

    if check_metadata_scope(url_base, scope) do
      url      = "#{url_base}/token"
      {:ok, token} = HTTPoison.get(url, headers)
      {:ok, Token.from_response_json(scope, token.body)}
    else
      {:error, :scope_denied}
    end
  end

  # Fetch an access token from Google's OAuth service using a JWT
  def get_access_token(:oauth, scope) do
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

  def claims(scope), do: claims(scope, :os.system_time(:seconds))
  def claims(scope, iat) do
    {:ok, email} = Config.get(:client_email)
    %{
      "iss"   => email,
      "scope" => scope,
      "aud"   => "https://www.googleapis.com/oauth2/v4/token",
      "iat"   => iat,
      "exp"   => iat+10
    }
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

  # The metadata service returns tokens regardless of the requested scope, but
  # scopes can be checked at the separate scopes endpoint.
  # This function takes care of that in order to verify scope for metadata
  # based token requests as well.
  def check_metadata_scope(url_base, requested) do
    headers  = [{"Metadata-Flavor", "Google"}]
    {:ok, scopes} = HTTPoison.get("#{url_base}/scopes", headers)
    scopes = String.split(scopes.body, "\n")

    requested
    |> String.split(" ")
    |> Enum.all?(fn(scope) -> Enum.member?(scopes, scope) end)
  end

  @doc "Retrieves the project ID from Google's metadata service"
  def retrieve_metadata_project do
    headers  = [{"Metadata-Flavor", "Google"}]
    endpoint = "computeMetadata/v1/project/project-id"

    case Application.get_env(:goth, :metadata_url) do
      metadata when is_binary(metadata) ->
        url = "#{metadata}/#{endpoint}"
        HTTPoison.get!(url, headers).body
      _ -> %{}
    end
  end
end
