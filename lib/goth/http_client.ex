defmodule Goth.HTTPClient do
  @moduledoc """
  Specification for a Goth HTTP client.

  The client is configured as a `{module, initial_state}` tuple where the module
  implements this behaviour and `initial_state` is returned by the `c:init/1`
  callback.

  The `c:init/1` callback gives an opportunity to perform some initialization tasks just once.
  """

  @type method() :: atom()

  @type url() :: binary()

  @type status() :: non_neg_integer()

  @type header() :: {binary(), binary()}

  @type body() :: binary()

  @type initial_state() :: map()

  @doc """
  Callback to initialize the given HTTP client.

  The returned `initial_state` needs to be a map and  will be given to `c:request/6`.
  """
  @callback init(opts :: keyword()) :: initial_state()

  @doc """
  Callback to make an HTTP request.
  """
  @callback request(method(), url(), [header()], body(), opts :: keyword(), initial_state()) ::
              {:ok, %{status: status, headers: [header()], body: body()}}
              | {:error, Exception.t()}

  @doc false
  def init({module, opts}) when is_atom(module) and is_list(opts) do
    initial_state = module.init(opts)

    unless is_map(initial_state) do
      raise "#{inspect(module)}.init/1 must return a map, got: #{inspect(initial_state)}"
    end

    {module, initial_state}
  end

  @doc false
  def request({module, initial_state}, method, url, headers, body, opts) do
    module.request(method, url, headers, body, opts, initial_state)
  end
end
