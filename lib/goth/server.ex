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
    max_retries: @max_retries,
    retries: @max_retries
  ]

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: registry_name(name))
  end

  def fetch(name) do
    name
    |> maybe_get_cache()
    |> maybe_fetch_token(name)
  end

  defp maybe_get_cache(name) do
    get(name)
  rescue
    ArgumentError -> {nil, nil}
  end

  defp maybe_fetch_token({_state, nil = _token}, name) do
    GenServer.call(registry_name(name), :fetch)
  end

  defp maybe_fetch_token({_state, token}, _) do
    {:ok, token}
  end

  defp maybe_fetch_token(_, _) do
    {:error, RuntimeError.exception("no token")}
  end

  @impl true
  def init(opts) when is_list(opts) do
    {backoff_opts, opts} = Keyword.split(opts, [:backoff_type, :backoff_min, :backoff_max])
    {prefetch, opts} = Keyword.pop(opts, :prefetch)

    state = struct!(__MODULE__, opts)

    state =
      state
      |> Map.update!(:http_client, &start_http_client/1)
      |> Map.replace!(:backoff, Backoff.new(backoff_opts))
      |> Map.replace!(:retries, state.max_retries)

    case prefetch || :sync do
      :async ->
        put(state, nil)
        {:ok, state, {:continue, :async_prefetch}}

      :sync ->
        do_prefetch(state)
        {:ok, state}
    end
  end

  @impl true
  def handle_continue(:async_prefetch, state) do
    do_prefetch(state)
    {:noreply, state}
  end

  defp do_prefetch(state) do
    # given calculating JWT for each request is expensive, we do it once
    # on system boot to hopefully fill in the cache.
    case Token.fetch(state) do
      {:ok, token} ->
        store_and_schedule_refresh(state, token)

      {:error, _} ->
        put(state, nil)
        send(self(), :refresh)
    end
  end

  @impl true
  def handle_call(:fetch, _from, state) do
    {:reply, Token.fetch(state), state}
  end

  defp start_http_client({module, opts}) do
    Goth.HTTPClient.init({module, opts})
  end

  @impl true
  def handle_info(:refresh, state) do
    case Token.fetch(state) do
      {:ok, token} -> do_refresh(token, state)
      {:error, exception} -> handle_retry(exception, state)
    end
  end

  defp handle_retry(exception, %{retries: 1}) do
    raise "too many failed attempts to refresh, last error: #{inspect(exception)}"
  end

  defp handle_retry(_, state) do
    {time_in_seconds, backoff} = Backoff.backoff(state.backoff)
    Process.send_after(self(), :refresh, time_in_seconds)

    {:noreply, %{state | retries: state.retries - 1, backoff: backoff}}
  end

  defp do_refresh(token, state) do
    state = %{state | retries: state.max_retries, backoff: Backoff.reset(state.backoff)}
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

  defp registry_name(name) do
    {:via, Registry, {@registry, name}}
  end
end
