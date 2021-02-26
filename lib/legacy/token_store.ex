defmodule Goth.TokenStore do
  @moduledoc false
  # The `Goth.TokenStore` is a simple `GenServer` that manages storage and retrieval
  # of tokens `Goth.Token`. When adding to the token store, it also queues tokens
  # for a refresh before they expire: ten seconds before the token is set to expire,
  # the `TokenStore` will call the API to get a new token and replace the expired
  # token in the store.

  use GenServer
  alias Goth.Token

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  @doc ~S"""
  Store a token in the `TokenStore`. Upon storage, Goth will queue the token
  to be refreshed ten seconds before its expiration.
  """
  @spec store(Token.t()) :: pid
  def store(%Token{} = token), do: store(token.scope, token.sub, token)

  @spec store({String.t() | atom(), String.t()} | String.t(), Token.t()) :: pid()
  def store(scopes, %Token{} = token) when is_binary(scopes),
    do: store({:default, scopes}, token.sub, token)

  def store({account, scopes}, %Token{} = token) when is_binary(scopes),
    do: store({account, scopes}, token.sub, token)

  @spec store(String.t(), String.t(), Token.t()) :: pid
  def store(scopes, sub, %Token{} = token) when is_binary(scopes),
    do: store({:default, scopes}, sub, token)

  @spec store({String.t() | atom(), String.t()}, String.t() | nil, Token.t()) :: pid
  def store({account, scopes}, sub, %Token{} = token) when is_binary(scopes) do
    GenServer.call(__MODULE__, {:store, {account, scopes, sub}, token})
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
  @spec find({String.t() | atom(), String.t()} | String.t(), String.t() | nil) ::
          {:ok, Token.t()} | :error
  def find(info, sub \\ nil)

  def find(scope, sub) when is_binary(scope), do: find({:default, scope}, sub)

  def find({account, scope}, sub) do
    GenServer.call(__MODULE__, {:find, {account, scope, sub}})
  end

  # when we store a token, we should refresh it later
  def handle_call({:store, {account, scope, sub}, token}, _from, state) do
    # this is a race condition when inserting an expired (or about to expire) token...
    pid_or_timer = Token.queue_for_refresh(token)
    {:reply, pid_or_timer, Map.put(state, {account, scope, sub}, token)}
  end

  def handle_call({:find, {account, scope, sub}}, _from, state) do
    state
    |> Map.fetch({account, scope, sub})
    |> filter_expired(:os.system_time(:seconds))
    |> reply(state, {account, scope, sub})
  end

  defp filter_expired(:error, _), do: :error

  defp filter_expired({:ok, %Goth.Token{expires: expires}}, system_time)
       when expires < system_time,
       do: :error

  defp filter_expired(value, _), do: value

  defp reply(:error, state, {account, scope, sub}),
    do: {:reply, :error, Map.delete(state, {account, scope, sub})}

  defp reply(value, state, _key), do: {:reply, value, state}
end
