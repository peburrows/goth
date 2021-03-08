defmodule Goth.HTTPClient.Hackney do
  @moduledoc """
  Hackney-based HTTP client adapter.

  ## Options

    * `:default_opts` - default options passed down to Hackney, see `:hackney.request/5` for
      more information.

  """

  @behaviour Goth.HTTPClient

  defstruct default_opts: []

  require Logger

  @impl true
  def init(opts) do
    unless Code.ensure_loaded?(:hackney) do
      Logger.error("""
      Could not find hackney dependency.

      Please add :hackney to your dependencies:

          {:hackney, "~> 1.17"}

      Or use a different HTTP client. See Goth.HTTPClient for more information.
      """)

      raise "missing hackney dependency"
    end

    {:ok, _} = Application.ensure_all_started(:hackney)
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
