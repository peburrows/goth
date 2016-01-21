defmodule Goth.Token do
  @moduledoc """
  Interface for retrieving access tokens, from either the `Goth.TokenStore`
  or the Google token API. The first request for a token will hit the API,
  but subsequent requests will retrieve the token from Goth's token store
  """

  alias Goth.TokenStore
  alias Goth.Client

  defstruct [:token, :type, :expires]

  @doc """
  Get a `%Goth.Token{}` for a particular `scope`. `scope` can be a single
  scope or multiple scopes joined by a comma.

  ## Example
  iex> Token.for_scope("https://www.googleapis.com/auth/pubsub")
  {:ok, %Goth.Token{expires: ..., token: "...", type: "..."} }
  """
  def for_scope(scope) do
    case TokenStore.find(scope) do
      :error       -> retrieve_and_store!(scope)
      {:ok, token} -> {:ok, token}
    end
  end

  @doc """
  Parse a successful JSON response from Google's token API and extract a `%Goth.Token{}`
  """

  def from_response_json(json) do
    {:ok, attrs} = json |> Poison.decode
    %__MODULE__{
      token:   attrs["access_token"],
      type:    attrs["token_type"],
      expires: :os.system_time(:seconds) + attrs["expires_in"]
    }
  end

  defp retrieve_and_store!(scope) do
    {:ok, token} = Client.get_access_token(scope)
    TokenStore.store(scope, token)
    {:ok, token}
  end
end
