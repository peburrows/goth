defmodule Goth.Token do
  @moduledoc ~S"""
  Interface for retrieving access tokens, from either the `Goth.TokenStore`
  or the Google token API. The first request for a token will hit the API,
  but subsequent requests will retrieve the token from Goth's token store.

  Goth will automatically refresh access tokens in the background as necessary,
  10 seconds before they are to expire. After the initial synchronous request to
  retrieve an access token, your application should never have to wait for a
  token again.

  The first call to retrieve an access token for a particular scope blocks while
  it hits the API. Subsequent calls pull from the `Goth.TokenStore`,
  and should return immediately

      iex> Goth.Token.for_scope("https://www.googleapis.com/auth/pubsub")
      {:ok, %Goth.Token{token: "23984723",
                        type: "Bearer",
                        scope: "https://www.googleapis.com/auth/pubsub",
                        expires: 1453653825,
                        account: :default}}

  If the passed credentials contain multiple service account, you can change
  the first parametter to be {client_email, scopes} to specify which account
  to target.

      iex> Goth.Token.for_scope({"myaccount@project.iam.gserviceaccount.com", "https://www.googleapis.com/auth/pubsub"})
      {:ok, %Goth.Token{token: "23984723",
                        type: "Bearer",
                        scope: "https://www.googleapis.com/auth/pubsub",
                        expires: 1453653825,
                        account: "myaccount@project.iam.gserviceaccount.com"}}

  For using the token on subsequent requests to the Google API, just concatenate
  the `type` and `token` to create the authorization header. An example using
  [HTTPoison](https://hex.pm/packages/httpoison):

      {:ok, token} = Goth.Token.for_scope("https://www.googleapis.com/auth/pubsub")
      HTTPoison.get(url, [{"Authorization", "#{token.type} #{token.token}"}])
  """

  alias Goth.TokenStore
  alias Goth.Client

  @type t :: %__MODULE__{
          token: String.t(),
          type: String.t(),
          scope: String.t(),
          sub: String.t() | nil,
          expires: non_neg_integer,
          account: String.t()
        }

  defstruct [:token, :type, :scope, :sub, :expires, :account]

  @doc """
  Get a `%Goth.Token{}` for a particular `scope`. `scope` can be a single
  scope or multiple scopes joined by a space.

  `sub` needs to be specified if impersonation is used to prevent cache
  leaking between users.

  ## Example
      iex> Token.for_scope("https://www.googleapis.com/auth/pubsub")
      {:ok, %Goth.Token{expires: ..., token: "...", type: "..."} }
  """
  @spec for_scope(scope :: String.t(), sub :: String.t() | nil) :: {:ok, t}
  def for_scope(info, sub \\ nil)

  def for_scope(scope, sub) when is_binary(scope) do
    case TokenStore.find({:default, scope}, sub) do
      :error -> retrieve_and_store!({:default, scope}, sub)
      {:ok, token} -> {:ok, token}
    end
  end

  @spec for_scope({info :: {String.t(), atom()} | atom()}, sub :: String.t() | nil) :: {:ok, t}
  def for_scope({account, scope}, sub) do
    case TokenStore.find({account, scope}, sub) do
      :error -> retrieve_and_store!({account, scope}, sub)
      {:ok, token} -> {:ok, token}
    end
  end

  @doc """
  Parse a successful JSON response from Google's token API and extract a `%Goth.Token{}`
  """
  def from_response_json(scope, sub \\ nil, json)

  @spec from_response_json(String.t(), String.t() | nil, String.t()) :: t
  def from_response_json(scope, sub, json) when is_binary(scope) do
    {:ok, attrs} = json |> Poison.decode()

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
    {:ok, attrs} = json |> Poison.decode()

    %__MODULE__{
      token: attrs["access_token"],
      type: attrs["token_type"],
      scope: scope,
      sub: sub,
      expires: :os.system_time(:seconds) + attrs["expires_in"],
      account: account
    }
  end

  @doc """
  Retrieve a new access token from the API. This is useful for expired tokens,
  although `Goth` automatically handles refreshing tokens for you, so you should
  rarely if ever actually need to call this method manually.
  """
  @spec refresh!(t | String.t()) :: {:ok, t}
  def refresh!(%__MODULE__{account: account, scope: scope, sub: sub}),
    do: refresh!({account, scope}, sub)

  def refresh!(%__MODULE__{account: account, scope: scope}), do: refresh!({account, scope})

  def refresh!({account, scope}, sub \\ nil), do: retrieve_and_store!({account, scope}, sub)

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
    {:ok, token} = Client.get_access_token({account, scope}, sub: sub)
    TokenStore.store({account, scope}, sub, token)
    {:ok, token}
  end
end
