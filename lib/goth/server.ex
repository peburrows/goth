defmodule Goth.Server do
  @moduledoc false

  use GenServer
  alias Goth.Token

  @max_retries 3
  @registry Goth.Registry

  defstruct [
    :name,
    :source,
    :http_client,
    :retry_after,
    :refresh_before,
    retries: @max_retries
  ]

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: registry_name(name))
  end

  def fetch(name) do
    GenServer.call(registry_name(name), :fetch)
  end

  @impl true
  def init(opts) when is_list(opts) do
    opts =
      Keyword.update!(opts, :http_client, fn {module, opts} ->
        Goth.HTTPClient.init({module, opts})
      end)

    state = struct!(__MODULE__, opts)

    {:ok, state, {:continue, :fetch_token}}
  end

  @impl true
  def handle_continue(:fetch_token, state) do
    # given calculating JWT for each request is expensive, we do it once
    # on system boot to hopefully fill in the cache.
    case Token.fetch(state) do
      {:ok, token} ->
        store_and_schedule_refresh(state, token)

      {:error, _} ->
        put(state, nil)
        send(self(), :refresh)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:fetch, _from, state) do
    {config, token} =
      try do
        get(state.name)
      rescue
        ArgumentError ->
          {nil, nil}
      end

    reply =
      cond do
        token ->
          {:ok, token}

        config == nil ->
          {:error, RuntimeError.exception("no token")}

        true ->
          Token.fetch(config)
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    case Token.fetch(state) do
      {:ok, token} ->
        store_and_schedule_refresh(state, token)
        {:noreply, %{state | retries: @max_retries}}

      {:error, exception} ->
        if state.retries > 1 do
          Process.send_after(self(), :refresh, state.retry_after)
          {:noreply, %{state | retries: state.retries - 1}}
        else
          raise "too many failed attempts to refresh, last error: #{inspect(exception)}"
        end
    end
  end

  defp store_and_schedule_refresh(state, token) do
    put(state, token)
    time_in_seconds = max(token.expires - System.system_time(:second) - state.refresh_before, 0)
    Process.send_after(self(), :refresh, time_in_seconds * 1000)
  end

  defp get(name) do
    [{_pid, data}] = Registry.lookup(@registry, name)
    data
  end

  defp put(state, token) do
    config = Map.take(state, [:source, :http_client])
    Registry.update_value(@registry, state.name, fn _ -> {config, token} end)
  end

  defp registry_name(name) do
    {:via, Registry, {@registry, name}}
  end
end
