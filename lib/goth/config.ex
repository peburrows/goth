defmodule Goth.Config do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  def init(:ok) do
    case Application.get_env(:goth, :json) do
      nil  -> {:ok, Application.get_env(:goth, :config, %{})}
      {:system, var} -> {:ok, Poison.decode!(System.get_env(var)) }
      json -> {:ok, Poison.decode!(json)}
    end
  end

  def set(key, value) when is_atom(key), do: key |> to_string |> set(value)
  def set(key, value) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  def get(key) when is_atom(key), do: key |> to_string |> get
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def handle_call({:set, key, value}, _from, keys) do
    {:reply, :ok, Map.put(keys, key, value)}
  end

  def handle_call({:get, key}, _from, keys) do
    {:reply, Map.fetch(keys, key), keys}
  end
end
