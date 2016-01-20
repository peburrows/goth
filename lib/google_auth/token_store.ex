defmodule GoogleAuth.TokenStore do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, [name: __MODULE__])
  end

  # we nee to store the actual expiration timestamp at some point
  def store(scopes, key, type, expires) do
    to_store = %{key: key, type: type, expires: expires}
    scopes |> String.split(~r{(\s*),(\s*)}) |> Enum.each(fn(scope)->
      GenServer.call(__MODULE__, {:store, scope, to_store})
    end)
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
