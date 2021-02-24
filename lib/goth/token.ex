defmodule Goth.Token do
  @moduledoc """
  Functions for retrieving the token from the Google API.
  """

  @type t :: %__MODULE__{
          token: String.t(),
          type: String.t(),
          scope: String.t(),
          expires: non_neg_integer
          # TODO: do we still need these?
          # account: String.t()
          # sub: String.t() | nil
        }

  defstruct [:token, :type, :scope, :sub, :expires, :account]

  @default_url "https://www.googleapis.com/oauth2/v4/token"

  @doc false
  def default_url(), do: @default_url

  @default_scope "https://www.googleapis.com/auth/cloud-platform"

  @doc false
  def default_scope(), do: @default_scope

  @doc """
  Fetch the token from the Google API using the given `config`.

  Config may contain the following keys:

    * `:credentials` - a map of credentials.

    * `:scope` - Token scope, defaults to `#{inspect(@default_scope)}`.

    * `:url` - URL to fetch the token from, defaults to `#{inspect(@default_url)}`.

    * `:http_opts` - Options passed to the underlying HTTP client, defaults to
      `[]`.

  """
  @doc since: "1.3.0"
  @spec fetch(map()) :: {:ok, t()} | {:error, term()}
  def fetch(config) when is_map(config) do
    jwt = jwt(config.scope, config.credentials)
    http_opts = Map.get(config, :http_opts, [])

    case request(config.url, jwt, http_opts) do
      {:ok, %{status_code: 200} = response} ->
        with {:ok, map} <- Jason.decode(response.body) do
          %{
            "access_token" => token,
            "expires_in" => expires_in,
            "token_type" => type
          } = map

          token = %__MODULE__{
            expires: System.system_time(:second) + expires_in,
            scope: config.scope,
            token: token,
            type: type
            # sub: ...,
            # account: ...
          }

          {:ok, token}
        end

      {:ok, response} ->
        message = """
        unexpected status #{response.status_code} from Google

        #{response.body}
        """

        {:error, RuntimeError.exception(message)}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp jwt(scope, %{
         "private_key" => private_key,
         "client_email" => client_email,
         "token_uri" => token_uri
       }) do
    jwk = JOSE.JWK.from_pem(private_key)
    header = %{"alg" => "RS256", "typ" => "JWT"}
    unix_time = System.system_time(:second)

    claim_set = %{
      "iss" => client_email,
      "scope" => scope,
      "aud" => token_uri,
      "exp" => unix_time + 3600,
      "iat" => unix_time
    }

    JOSE.JWT.sign(jwk, header, claim_set) |> JOSE.JWS.compact() |> elem(1)
  end

  defp request(url, jwt, opts) do
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"
    body = "grant_type=#{grant_type}&assertion=#{jwt}"
    HTTPoison.request(:post, url, body, headers, opts)
  end

  # Everything below is deprecated.

  alias Goth.TokenStore
  alias Goth.Client

  # Get a `%Goth.Token{}` for a particular `scope`. `scope` can be a single
  # scope or multiple scopes joined by a space. See [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/googlescopes) for all available scopes.

  # `sub` needs to be specified if impersonation is used to prevent cache
  # leaking between users.

  # ## Example
  #     iex> Token.for_scope("https://www.googleapis.com/auth/pubsub")
  #     {:ok, %Goth.Token{expires: ..., token: "...", type: "..."} }
  @doc false
  def for_scope(info, sub \\ nil)

  @spec for_scope(scope :: String.t(), sub :: String.t() | nil) :: {:ok, t} | {:error, any()}
  def for_scope(scope, sub) when is_binary(scope) do
    case TokenStore.find({:default, scope}, sub) do
      :error -> retrieve_and_store!({:default, scope}, sub)
      {:ok, token} -> {:ok, token}
    end
  end

  @spec for_scope(info :: {String.t() | atom(), String.t()}, sub :: String.t() | nil) ::
          {:ok, t} | {:error, any()}
  def for_scope({account, scope}, sub) do
    case TokenStore.find({account, scope}, sub) do
      :error -> retrieve_and_store!({account, scope}, sub)
      {:ok, token} -> {:ok, token}
    end
  end

  @doc false
  # Parse a successful JSON response from Google's token API and extract a `%Goth.Token{}`
  def from_response_json(scope, sub \\ nil, json)

  @spec from_response_json(String.t(), String.t() | nil, String.t()) :: t
  def from_response_json(scope, sub, json) when is_binary(scope) do
    {:ok, attrs} = json |> Jason.decode()

    %__MODULE__{
      token: attrs["access_token"],
      type: attrs["token_type"],
      scope: scope,
      sub: sub,
      expires: :os.system_time(:seconds) + attrs["expires_in"],
      account: :default
    }
  end

  @spec from_response_json(
          {atom() | String.t(), String.t()},
          String.t() | nil,
          String.t()
        ) :: t
  def from_response_json({account, scope}, sub, json) do
    {:ok, attrs} = json |> Jason.decode()

    %__MODULE__{
      token: attrs["access_token"],
      type: attrs["token_type"],
      scope: scope,
      sub: sub,
      expires: :os.system_time(:seconds) + attrs["expires_in"],
      account: account
    }
  end

  # Retrieve a new access token from the API. This is useful for expired tokens,
  # although `Goth` automatically handles refreshing tokens for you, so you should
  # rarely if ever actually need to call this method manually.
  @doc false
  @spec refresh!(t() | {any(), any()}) :: {:ok, t()}
  def refresh!(%__MODULE__{account: account, scope: scope, sub: sub}),
    do: refresh!({account, scope}, sub)

  def refresh!(%__MODULE__{account: account, scope: scope}), do: refresh!({account, scope})

  @doc false
  @spec refresh!({any(), any()}, any()) :: {:ok, t()}
  def refresh!({account, scope}, sub \\ nil), do: retrieve_and_store!({account, scope}, sub)

  @doc false
  def queue_for_refresh(%__MODULE__{} = token) do
    diff = token.expires - :os.system_time(:seconds)

    if diff < 10 do
      # just do it immediately
      Task.async(fn ->
        __MODULE__.refresh!(token)
      end)
    else
      :timer.apply_after((diff - 10) * 1000, __MODULE__, :refresh!, [token])
    end
  end

  defp retrieve_and_store!({account, scope}, sub) do
    Client.get_access_token({account, scope}, sub: sub)
    |> case do
      {:ok, token} ->
        TokenStore.store({account, scope}, sub, token)
        {:ok, token}

      other ->
        other
    end
  end
end
