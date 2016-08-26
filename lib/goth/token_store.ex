defmodule Goth.TokenStore do
  @moduledoc """
  The `Goth.TokenStore` is a simple `GenServer` that manages storage and retrieval
  of tokens `Goth.Token`. When adding to the token store, it also queues tokens
  for a refresh before they expire: ten seconds before the token is set to expire,
  the `TokenStore` will call the API to get a new token and replace the expired
  token in the store.
  """

  use GenServer
  alias Goth.Token

  def start_link do
    GenServer.start_link(__MODULE__, %{}, [name: __MODULE__])
  end

  @doc ~S"""
  Store a token in the `TokenStore`. Upon storage, Goth will queue the token
  to be refreshed ten seconds before its expiration.
  """
  @spec store(Token.t) :: pid
  def store(%Token{}=token), do: store(token.scope, token)
  def store(scopes, %Token{} = token) do
    GenServer.call(__MODULE__, {:store, scopes, token})
  end

  @doc ~S"""
  Retrieve a token from the `TokenStore`.

      token = %Goth.Token{type:    "Bearer",
                          token:   "123",
                          scope:   "scope",
                          expires: :os.system_time(:seconds) + 3600}
      Goth.TokenStore.store(token)
      {:ok, ^token} = Goth.TokenStore.find(token.scope)
  """
  @spec find(String.t) :: {:ok, Token.t} | :error
  def find(scope) do
    GenServer.call(__MODULE__, {:find, scope})
  end

  # when we store a token, we should refresh it later
  def handle_call({:store, scope, token}, _from, state) do
    # this is a race condition when inserting an expired (or about to expire) token...
    pid_or_timer = Token.queue_for_refresh(token)
    {:reply, pid_or_timer, Map.put(state, scope, token)}
  end

  def handle_call({:find, scope}, _from, state) do
    state
    |> Map.fetch(scope)
    |> filter_expired(:os.system_time(:seconds))
    |> reply(state, scope)
  end

  defp filter_expired(:error, _), do: :error
  defp filter_expired({:ok, %Goth.Token{expires: expires}}, system_time) when expires < system_time, do: :error
  defp filter_expired(value, _), do: value
  defp reply(:error, state, scope), do: {:reply, :error, Map.delete(state, scope)}
  defp reply(value, state, _scope), do: {:reply, value, state}
end
