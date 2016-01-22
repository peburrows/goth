defmodule Goth.TokenStore do
  use GenServer
  alias Goth.Token

  def start_link do
    GenServer.start_link(__MODULE__, %{}, [name: __MODULE__])
  end

  def store(%Token{}=token), do: store(token.scope, token)
  def store(scopes, %Token{} = token) do
    GenServer.call(__MODULE__, {:store, scopes, token})
  end

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
    {:reply, Map.fetch(state, scope), state}
  end
end
