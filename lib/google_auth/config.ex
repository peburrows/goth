defmodule GoogleAuth.Config do
  use GenServer

  def start_link(state, opts \\ []) do
    GenServer.start_link(__MODULE__, state, opts)
  end

  def set(server, key, value) do
    GenServer.call(server, {:set, key, value})
  end

  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  def handle_call({:set, key, value}, _from, keys) do
    {:reply, :ok, Map.put(keys, key, value)}
  end

  def handle_call({:get, key}, _from, keys) do
    {:reply, Map.fetch(keys, key), keys}
  end
end
