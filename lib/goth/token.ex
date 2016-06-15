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
                        expires: 1453653825}}

  For using the token on subsequent requests to the Google API, just concatenate
  the `type` and `token` to create the authorization header. An example using
  [HTTPoison](https://hex.pm/packages/httpoison):

      {:ok, token} = Goth.Token.for_scope("https://www.googleapis.com/auth/pubsub")
      HTTPoison.get(url, [{"Authorization", "#{token.type} #{token.token}"}])
  """

  alias Goth.TokenStore
  alias Goth.Client

  @type t :: %__MODULE__{
                    token: String.t,
                    type:  String.t,
                    scope: String.t,
                    expires: non_neg_integer
                  }

  defstruct [:token, :type, :scope, :expires]

  @doc """
  Get a `%Goth.Token{}` for a particular `scope`. `scope` can be a single
  scope or multiple scopes joined by a space.

  ## Example
      iex> Token.for_scope("https://www.googleapis.com/auth/pubsub")
      {:ok, %Goth.Token{expires: ..., token: "...", type: "..."} }
  """
  @spec for_scope(String.t) :: {:ok, t} | :error
  def for_scope(scope) do
    case TokenStore.find(scope) do
      :error       -> retrieve_and_store!(scope)
      {:ok, token} -> {:ok, token}
    end
  end

  @doc """
  Parse a successful JSON response from Google's token API and extract a `%Goth.Token{}`
  """
  @spec from_response_json(String.t, String.t) :: t
  def from_response_json(scope, json) do
    {:ok, attrs} = json |> Poison.decode
    %__MODULE__{
      token:   attrs["access_token"],
      type:    attrs["token_type"],
      scope:   scope,
      expires: :os.system_time(:seconds) + attrs["expires_in"]
    }
  end

  @doc """
  Retrieve a new access token from the API. This is useful for expired tokens,
  although `Goth` automatically handles refreshing tokens for you, so you should
  rarely if ever actually need to call this method manually.
  """
  @spec refresh!(t | String.t) :: {:ok, t}
  def refresh!(%__MODULE__{scope: scope}), do: refresh!(scope)
  def refresh!(scope), do: retrieve_and_store!(scope)

  def queue_for_refresh(%__MODULE__{}=token) do
    diff = token.expires - :os.system_time(:seconds)
    if diff < 10 do
      # just do it immediately
      Task.async fn ->
        __MODULE__.refresh!(token)
      end
    else
      :timer.apply_after((diff-10)*1000, __MODULE__, :refresh!, [token])
    end
  end

  defp retrieve_and_store!(scope) do
    {:ok, token} = Client.get_access_token(scope)
    TokenStore.store(scope, token)
    {:ok, token}
  end
end
