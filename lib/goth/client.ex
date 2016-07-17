defmodule Goth.Client do
  alias Goth.Config
  alias Goth.Token

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
    {:ok, Token.from_response_json(scope, response.body)}
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
  def json(scope, iat), do: claims(scope, iat) |> Poison.encode!

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
end
