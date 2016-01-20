defmodule GoogleAuth.TokenStore do
  use GenServer
  alias GoogleAuth.Token

  def start_link do
    GenServer.start_link(__MODULE__, %{}, [name: __MODULE__])
  end

  # we nee to store the actual expiration timestamp at some point
  def store(scopes, %Token{} = token) do
    GenServer.call(__MODULE__, {:store, scopes, token})
  end

  def find(scope) do
    GenServer.call(__MODULE__, {:find, scope})
  end

  def handle_call({:store, scope, value}, _from, state) do
    {:reply, :ok, Map.put(state, scope, value)}
  end

  def handle_call({:find, scope}, _from, state) do
    {:reply, Map.fetch(state, scope), state}
  end
end
