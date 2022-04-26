defmodule Goth.Server do
  @moduledoc false
  use GenServer

  alias Goth.Backoff
  alias Goth.Token

  @max_retries 20
  @registry Goth.Registry

  defstruct [
    :name,
    :source,
    :backoff,
    :http_client,
    :retry_after,
    :refresh_before,
    retries: @max_retries
  ]

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {@registry, name}})
  end

  def fetch(server) do
    {config, token} =
      try do
        get(server)
      rescue
        ArgumentError ->
          {nil, nil}
      end

    cond do
      token ->
        {:ok, token}

      config == nil ->
        {:error, RuntimeError.exception("no token")}

      true ->
        Token.fetch(config)
    end
  end

  @impl true
  def init(opts) when is_list(opts) do
    opts =
      opts
      |> Keyword.update!(:http_client, &start_http_client/1)
      |> Keyword.put(:backoff, start_backoff(opts[:backoff]))

    state = struct!(__MODULE__, opts)

    # given calculating JWT for each request is expensive, we do it once
    # on system boot to hopefully fill in the cache.
    case Token.fetch(state) do
      {:ok, token} ->
        store_and_schedule_refresh(state, token)

      {:error, _} ->
        put(state, nil)
        send(self(), :refresh)
    end

    {:ok, state}
  end

  defp start_http_client({module, opts}) do
    Goth.HTTPClient.init({module, opts})
  end

  defp start_backoff(nil) do
    Backoff.new!([])
  end

  defp start_backoff(opts) do
    Backoff.new!(opts)
  end

  @impl true
  def handle_info(:refresh, state) do
    state
    |> Token.fetch()
    |> handle_refresh(state)
  end

  defp handle_refresh({:error, exception}, %{retries: 1}) do
    raise "too many failed attempts to refresh, last error: #{inspect(exception)}"
  end

  defp handle_refresh({:error, _}, %{retries: retries, backoff: backoff} = state) do
    {time_in_seconds, backoff} = Backoff.backoff(backoff)
    Process.send_after(self(), :refresh, time_in_seconds)

    {:noreply, %{state | retries: retries - 1, backoff: backoff}}
  end

  defp handle_refresh({:ok, token}, %{backoff: backoff} = state) do
    state = %{state | retries: @max_retries, backoff: Backoff.reset(backoff)}
    store_and_schedule_refresh(state, token)

    {:noreply, state}
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
end
