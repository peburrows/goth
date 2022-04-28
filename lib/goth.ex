defmodule Goth do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @doc """
  Fetches the token.

  If the token is not in the cache, we send a message to the given
  GenServer to immediately request it.

  It also allows to pass the timeout that we should use when calling
  the GenServer.

  To fetch the token bypassing the cache, see `Goth.Token.fetch/2`.
  """
  @doc since: "1.3.0"
  defdelegate fetch(server, timeout \\ 5000), to: Goth.Server

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

    * `:http_client` - a `{module, opts}` tuple, where `module` implements the
      `Goth.HTTPClient` behaviour and `opts` is a keywords list to initialize the client with.
      Defaults to `{Goth.HTTPClient.Hackney, []}`.

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
    opts |> with_default_opts() |> Goth.Server.start_link()
  end

  @doc """
  Returns a supervision child spec.

  Accepts the same options as `start_link/1`.
  """
  @doc since: "1.3.0"
  def child_spec(opts) do
    opts |> with_default_opts() |> Goth.Server.child_spec()
  end

  defp with_default_opts(opts) do
    opts
    |> Keyword.put_new(:refresh_before, @refresh_before_minutes * 60)
    |> Keyword.put_new(:http_client, {Goth.HTTPClient.Hackney, []})
  end
end
