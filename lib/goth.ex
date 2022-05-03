defmodule Goth do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  use GenServer

  require Logger

  alias Goth.Backoff
  alias Goth.Token

  @registry Goth.Registry
  @max_retries 20
  @refresh_before_minutes 5

  @doc """
  Starts the server.

  When the server is started, we attempt to fetch the token and store it in
  internal cache. If we fail, we'll retry with backoff.

  ## Options

    * `:name` - a unique name to register the server under. It can be any term.

    * `:source` - the source to retrieve the token from.

      See documentation for the `:source` option in `Goth.Token.fetch/1` for
      more information.

    * `:refresh_before` - Time in seconds before the token is about to expire
      that it is tried to be automatically refreshed. Defaults to
      `#{@refresh_before_minutes * 60}` (#{@refresh_before_minutes} minutes).

    * `:http_client` - a `{&fun/1, opts}` tuple or `&fun/1`, where `fun` is a
      function reference with arity 1 and `opts` is a keywords list to initialize the client with.
      The function will receive a keyword list with required fields: `:method`, `:url`, `:body` and
      `:headers`, and `opts` merged into it, if available. And the function should return
      `{:ok, map} | {:error, exception}`. Defaults to `{&Goth.__hackney__/1, []}`.

    * `:http_client` - a function that makes the HTTP request. Can be one of the following:

      * `fun` - same as `{fun, []}`

      * `{fun, opts}` - `fun` must be a 1-arity function that receives a keyword list with fields
        `:method`, `:url`, `:headers`, and `:body` along with any passed `opts`. The function must return
        `{:ok, %{status: status, headers: headers, body: body}}` or `{:error, exception}`.
        Example: `{&HTTPClient.request/1, connect_timeout: 5000}`.

        `fun` can also be an atom `:hackney` to use the built-in [Hackney](http://github.com/benoitc/hackney)-based
        client.

      Defaults to `{:hackney, []}`

    * `:max_retries` - the maximum number of retries (default: `20`)

    * `:backoff_min` - the minimum backoff interval (default: `1_000`)

    * `:backoff_max` - the maximum backoff interval (default: `30_000`)

    * `:backoff_type` - the backoff strategy, `:exp` for exponential, `:rand` for random and
      `:rand_exp` for random exponential (default: `:rand_exp`)

    * `:prefetch` - the prefetch strategy, `:sync` to make the system boot with prefetch synchronous;
      `:async` to make the system boot with prefetch asynchronous.

  ## Examples

  Generate a token using a service account credentials file:

      iex> credentials = "credentials.json" |> File.read!() |> Jason.decode!()
      iex> Goth.start_link(name: MyApp.Goth, source: {:service_account, credentials, []})
      iex> Goth.fetch(MyApp.Goth)
      {:ok, %Goth.Token{...}}

  Retrieve the token using a refresh token:

      iex> credentials = "credentials.json" |> File.read!() |> Jason.decode!()
      iex> Goth.start_link(name: MyApp.Goth, source: {:refresh_token, credentials, []})
      iex> Goth.fetch(MyApp.Goth)
      {:ok, %Goth.Token{...}}

  Retrieve the token using the Google metadata server:

      iex> Goth.start_link(name: MyApp.Goth, source: {:metadata, []})
      iex> Goth.fetch(MyApp.Goth)
      {:ok, %Goth.Token{...}}

  """
  @doc since: "1.3.0"
  def start_link(opts) do
    opts =
      opts
      |> Keyword.put_new(:refresh_before, @refresh_before_minutes * 60)
      |> Keyword.put_new(:http_client, {:hackney, []})

    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: registry_name(name))
  end

  defmacrop ensure_hackney do
    if Code.ensure_loaded?(:hackney) do
      :ok
    else
      quote do
        unless Code.ensure_loaded?(:hackney) do
          Logger.error("""
          Could not find hackney dependency.

          Please add :hackney to your dependencies:

              {:hackney, "~> 1.17"}

          Or use a different HTTP client. See Goth for more information.
          """)

          raise "missing hackney dependency"
        end

        {:ok, _} = Application.ensure_all_started(:hackney)

        :ok
      end
    end
  end

  def __hackney__(options) do
    ensure_hackney()

    {method, options} = Keyword.pop!(options, :method)
    {url, options} = Keyword.pop!(options, :url)
    {headers, options} = Keyword.pop!(options, :headers)
    {body, options} = Keyword.pop!(options, :body)
    options = [:with_body] ++ options

    case :hackney.request(method, url, headers, body, options) do
      {:ok, status, headers, response_body} ->
        {:ok, %{status: status, headers: headers, body: response_body}}

      {:error, reason} ->
        {:error, RuntimeError.exception(inspect(reason))}
    end
  end

  @doc """
  Fetches the token.

  If the token is not in the cache, we send a message to the given
  GenServer to immediately request it.

  It also allows to pass the timeout that we should use when calling
  the GenServer.

  To fetch the token bypassing the cache, see `Goth.Token.fetch/2`.
  """
  @doc since: "1.3.0"

  def fetch(name, timeout \\ 5000) do
    read_from_ets(name) || GenServer.call(registry_name(name), :fetch, timeout)
  end

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

  defp read_from_ets(name) do
    case Registry.lookup(@registry, name) do
      [{_pid, %Token{} = token}] -> {:ok, token}
      _ -> nil
    end
  end

  @impl true
  def init(opts) when is_list(opts) do
    {backoff_opts, opts} = Keyword.split(opts, [:backoff_type, :backoff_min, :backoff_max])
    {prefetch, opts} = Keyword.pop(opts, :prefetch, :async)

    state = struct!(__MODULE__, opts)

    state =
      state
      |> Map.update!(:http_client, &start_http_client/1)
      |> Map.replace!(:backoff, Backoff.new(backoff_opts))
      |> Map.replace!(:retries, state.max_retries)

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

  defp start_http_client(:hackney) do
    {&__hackney__/1, []}
  end

  defp start_http_client({:hackney, opts}) do
    {&__hackney__/1, opts}
  end

  defp start_http_client(func) when is_function(func, 1) do
    {func, []}
  end

  defp start_http_client({func, opts}) when is_function(func, 1) do
    {func, opts}
  end

  defp start_http_client({module, _} = config) when is_atom(module) do
    Logger.warn("Setting http_client: {mod, opts} is deprecated in favour of http_client: fun | {fun, opts}")

    Goth.HTTPClient.init(config)
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
    put(state.name, token)
    time_in_seconds = max(token.expires - System.system_time(:second) - state.refresh_before, 0)
    Process.send_after(self(), :refresh, time_in_seconds * 1000)
  end

  defp put(name, token) do
    Registry.update_value(@registry, name, fn _ -> token end)
  end

  defp registry_name(name) do
    {:via, Registry, {@registry, name}}
  end
end
