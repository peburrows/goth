defmodule Goth.HTTPClient.Hackney do
  @moduledoc """
  Hackney-based HTTP client adapter.

  ## Options

    * `:default_opts` - default options passed down to Hackney, see `:hackney.request/5` for
      more information.

  """

  @behaviour Goth.HTTPClient

  defstruct default_opts: []

  @impl true
  def init(opts) do
    struct!(__MODULE__, opts)
  end

  @impl true
  def request(method, url, headers, body, opts, state) do
    opts = Keyword.merge(state.default_opts, opts)

    with {:ok, status, headers, body_ref} <- :hackney.request(method, url, headers, body, opts),
         {:ok, body} <- :hackney.body(body_ref) do
      {:ok, %{status: status, headers: headers, body: body}}
    end
  end
end
