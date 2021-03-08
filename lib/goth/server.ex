defmodule Goth.Server do
  @moduledoc false

  # remove when we require OTP 22
  unless Code.ensure_loaded?(:persistent_term) do
    raise "#{inspect(__MODULE__)} uses :persistent_term and thus requires OTP 21.2"
  end

  use GenServer
  alias Goth.Token

  @max_retries 3

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
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def fetch(server) do
    {config, token} = get(server)

    if token do
      {:ok, token}
    else
      Token.fetch(config)
    end
  end

  @impl true
  def init(opts) when is_list(opts) do
    opts =
      Keyword.update!(opts, :http_client, fn {module, opts} ->
        Goth.HTTPClient.init({module, opts})
      end)

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
    :persistent_term.get({__MODULE__, name})
  end

  defp put(state, token) do
    config = Map.take(state, [:source, :http_client])
    :persistent_term.put({__MODULE__, state.name}, {config, token})
  end
end
