defmodule Goth.Config do
  use GenServer
  alias Goth.Client

  def start_link do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  def init(:ok) do
    case Application.get_env(:goth, :json) do
      nil  -> {:ok, Application.get_env(:goth, :config,
                %{"token_source" => :metadata,
                  "project_id" => Client.retrieve_metadata_project()})}
      {:system, var} -> {:ok, decode_json(System.get_env(var)) }
      json -> {:ok, decode_json(json)}
    end
  end

  # Decodes JSON (if configured) and sets oauth token source
  defp decode_json(json) do
    Poison.decode!(json)
    |> Map.put("token_source", :oauth)
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
