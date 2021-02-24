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

  @type initial_state() :: term()

  @doc """
  Callback to initialize the given HTTP client.

  The returned `initial_state` will be given to `c:request/6`.
  """
  @callback init(opts :: keyword()) :: initial_state()

  @doc """
  Callback to make an HTTP request.
  """
  @callback request(method(), url(), [header()], body(), opts :: keyword(), initial_state()) ::
              {:ok, %{status: status, headers: [header()], body: body()}}
              | {:error, Exception.t()}

  @doc false
  def request({module, initial_state}, method, url, headers, body, opts) do
    module.request(method, url, headers, body, opts, initial_state)
  end
end
