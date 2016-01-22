defmodule Goth.Token do
  @moduledoc """
  Interface for retrieving access tokens, from either the `Goth.TokenStore`
  or the Google token API. The first request for a token will hit the API,
  but subsequent requests will retrieve the token from Goth's token store
  """

  alias Goth.TokenStore
  alias Goth.Client

  @type token :: %__MODULE__{
                    token: String.t,
                    type:  String.t,
                    scope: String.t,
                    expires: non_neg_integer
                  }

  defstruct [:token, :type, :scope, :expires]

  @doc """
  Get a `%Goth.Token{}` for a particular `scope`. `scope` can be a single
  scope or multiple scopes joined by a comma.

  ## Example
      iex> Token.for_scope("https://www.googleapis.com/auth/pubsub")
      {:ok, %Goth.Token{expires: ..., token: "...", type: "..."} }
  """
  @spec for_scope(String.t) :: {:ok, token} | :error
  def for_scope(scope) do
    case TokenStore.find(scope) do
      :error       -> retrieve_and_store!(scope)
      {:ok, token} -> {:ok, token}
    end
  end

  @doc """
  Parse a successful JSON response from Google's token API and extract a `%Goth.Token{}`
  """

  def from_response_json(scope, json) do
    {:ok, attrs} = json |> Poison.decode
    %__MODULE__{
      token:   attrs["access_token"],
      type:    attrs["token_type"],
      scope:   scope,
      expires: :os.system_time(:seconds) + attrs["expires_in"]
    }
  end

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
