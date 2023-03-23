defmodule Goth do
  @moduledoc """
  A Goth token server.
  """

  use GenServer

  require Logger

  alias Goth.Token

  @registry Goth.Registry
  @max_retries 10
  @refresh_before_minutes 5

  @doc """
  Starts the server.

  When the server is started, we attempt to fetch the token and store it in
  internal cache. If we fail, we'll retry with backoff.

  ## Options

    * `:name` - a unique name to register the server under. It can be any term.

    * `:source` - the source to retrieve the token from.

      Supported values include:

        * `{:service_account, credentials}` - fetch token using service account credentials

        * `{:refresh_token, credentials}` - fetch token using refresh token

        * `:metadata` - fetching token using Google internal metadata service

      If `:source` is not set, Goth will:

        * Check application environment. You can set it with: `config :goth, json: File.read!("credentials.json")`.

        * Check `GOOGLE_APPLICATION_CREDENTIALS` env variable that contains path to credentials file.

        * Check `GOOGLE_APPLICATION_CREDENTIALS_JSON` env variable that contains credentials JSON.

        * Check `~/.config/gcloud/application_default_credentials.json` file.

        * Check `~/.config/gcloud/configurations/config_default` for project id and email address for SDK users.

        * Check Google internal metadata service

        * Otherwise, raise an error.

      See documentation of the "Source" section in `Goth.Token.fetch/1` documentation
      for more information.

    * `:refresh_before` - Time in seconds before the token is about to expire
      that it is tried to be automatically refreshed. Defaults to
      `#{@refresh_before_minutes * 60}` (#{@refresh_before_minutes} minutes).

    * `:http_client` - a function that makes the HTTP request. Defaults to using built-in
      integration with [Finch](https://github.com/sneako/finch)

      See documentation of the `:http_client` option in `Goth.Token.fetch/1` for
      more information.

    * `:prefetch` - how to prefetch the token when the server starts. The possible options
      are `:async` to do it asynchronously or `:sync` to do it synchronously
      (that is, the server doesn't start until an attempt to fetch the token was made). Defaults
      to `:async`.

    * `:max_retries` - the maximum number of retries (default: `#{@max_retries}`)

    * `:retry_delay` - a function that receives the retry count (starting at 0) and returns the delay, the
      number of milliseconds to sleep before making another attempt.
      Defaults to a simple exponential backoff capped at 30s: 1s, 2s, 4s, 8s, 16s, 30s, 30s, ...

  ## Examples

  Generate a token using a service account credentials file:

      iex> credentials = "credentials.json" |> File.read!() |> Jason.decode!()
      iex> {:ok, _} = Goth.start_link(name: MyApp.Goth, source: {:service_account, credentials, []})
      iex> Goth.fetch!(MyApp.Goth)
      %Goth.Token{...}

  Retrieve the token using a refresh token:

      iex> credentials = "credentials.json" |> File.read!() |> Jason.decode!()
      iex> {:ok, _} = Goth.start_link(name: MyApp.Goth, source: {:refresh_token, credentials, []})
      iex> Goth.fetch!(MyApp.Goth)
      %Goth.Token{...}

  Retrieve the token using the Google metadata server:

      iex> {:ok, _} = Goth.start_link(name: MyApp.Goth, source: {:metadata, []})
      iex> Goth.fetch!(MyApp.Goth)
      %Goth.Token{...}

  """
  @doc since: "1.3.0"
  def start_link(opts) do
    opts =
      opts
      |> Keyword.put_new(:refresh_before, @refresh_before_minutes * 60)
      |> Keyword.put_new(:http_client, {:finch, []})
      |> Keyword.put_new(:source, {:default, []})
      |> Keyword.put_new(:retry_delay, &exp_backoff/1)

    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: registry_name(name))
  end

  def __finch__(options) do
    {method, options} = Keyword.pop!(options, :method)
    {url, options} = Keyword.pop!(options, :url)
    {headers, options} = Keyword.pop!(options, :headers)
    {body, options} = Keyword.pop!(options, :body)

    finch_request = Finch.build(method, url, headers, body)

    Finch.request(finch_request, Goth.Finch, options)
  end

  @doc """
  Fetches the token from the cache.

  If the token is not in the cache, this function blocks for `timeout`
  milliseconds (defaults to `5000`) while it is attempted to fetch
  it in the background.

  To fetch the token bypassing the cache, see `Goth.Token.fetch/1`.
  """
  @doc since: "1.3.0"
  def fetch(name, timeout \\ 5000) do
    read_from_ets(name) || GenServer.call(registry_name(name), :fetch, timeout)
  end

  @doc """
  Fetches the token, erroring if it is missing.

  See `fetch/2` for more information.
  """
  @doc since: "1.3.0"
  def fetch!(name, timeout \\ 5000) do
    case fetch(name, timeout) do
      {:ok, token} -> token
      {:error, exception} -> raise exception
    end
  end

  defstruct [
    :name,
    :source,
    :retry_delay,
    :http_client,
    :retry_after,
    :refresh_before,
    max_retries: @max_retries,
    retries: 0
  ]

  defp read_from_ets(name) do
    now = System.system_time(:second)

    case Registry.lookup(@registry, name) do
      [{_pid, %Token{expires: expires}}] when expires <= now -> nil
      [{_pid, %Token{} = token}] -> {:ok, token}
      _ -> nil
    end
  end

  @impl true
  def init(opts) when is_list(opts) do
    {prefetch, opts} = Keyword.pop(opts, :prefetch, :async)

    state = struct!(__MODULE__, opts)
    state = Map.update!(state, :http_client, &start_http_client/1)

    case prefetch do
      :async ->
        {:ok, state, {:continue, :async_prefetch}}

      :sync ->
        prefetch(state)
        {:ok, state}
    end
  end

  @impl true
  def handle_continue(:async_prefetch, state) do
    prefetch(state)
    {:noreply, state}
  end

  defp prefetch(state) do
    # given calculating JWT for each request is expensive, we do it once
    # on system boot to hopefully fill in the cache.
    case Token.fetch(state) do
      {:ok, token} ->
        store_and_schedule_refresh(state, token)

      {:error, _} ->
        send(self(), :refresh)
    end
  end

  @impl true
  def handle_call(:fetch, _from, state) do
    reply = read_from_ets(state.name) || fetch_and_schedule_refresh(state)
    {:reply, reply, state}
  end

  defp fetch_and_schedule_refresh(state) do
    with {:ok, token} <- Token.fetch(state) do
      store_and_schedule_refresh(state, token)
      {:ok, token}
    end
  end

  defp start_http_client(:finch) do
    {&__finch__/1, []}
  end

  defp start_http_client({:finch, opts}) do
    {&__finch__/1, opts}
  end

  defp start_http_client(fun) when is_function(fun, 1) do
    {fun, []}
  end

  defp start_http_client({fun, opts}) when is_function(fun, 1) do
    {fun, opts}
  end

  defp start_http_client({module, _} = config) when is_atom(module) do
    Logger.warn("Setting http_client: mod | {mod, opts} is deprecated in favour of http_client: fun | {fun, opts}")

    Goth.HTTPClient.init(config)
  end

  @impl true
  def handle_info(:refresh, state) do
    case Token.fetch(state) do
      {:ok, token} -> do_refresh(token, state)
      {:error, exception} -> handle_retry(exception, state)
    end
  end

  defp handle_retry(exception, %{retries: retries, max_retries: max_retries}) when retries >= max_retries - 1 do
    raise "too many failed attempts to refresh, last error: #{inspect(exception)}"
  end

  defp handle_retry(_, state) do
    state = %{state | retries: state.retries + 1}
    time_in_milliseconds = state.retry_delay.(state.retries)
    Process.send_after(self(), :refresh, time_in_milliseconds)

    {:noreply, state}
  end

  defp do_refresh(token, state) do
    state = %{state | retries: 0}
    store_and_schedule_refresh(state, token)

    {:noreply, state}
  end

  defp store_and_schedule_refresh(state, token) do
    put(state.name, token)
    time_in_seconds = max(token.expires - System.system_time(:second) - state.refresh_before, 0)

    Process.send_after(self(), :refresh, time_in_seconds * 1000)
  end

  defp exp_backoff(retry_count) do
    min(30, round(:math.pow(2, retry_count))) * 1000
  end

  defp put(name, token) do
    Registry.update_value(@registry, name, fn _ -> token end)
  end

  defp registry_name(name) do
    {:via, Registry, {@registry, name}}
  end
end
