defmodule Goth.HTTPClient.Finch do
  @moduledoc false
  @behaviour Goth.HTTPClient

  defstruct default_opts: []

  require Logger

  @impl true
  def init(opts) do
    unless Code.ensure_loaded?(Finch) do
      Logger.error("""
      Could not find finch dependency.

      Please add :finch to your dependencies:

          {:finch, "~> 0.9.0 or ~> 0.10.0 or ~> 0.11.0 or ~> 0.12.0"},

      Or use a different HTTP client. See Goth.Token.fetch/1 documentation for more information.
      """)

      raise "missing finch dependency"
    end

    {:ok, _} = Application.ensure_all_started(:finch)
    struct!(__MODULE__, opts)
  end

  @impl true
  def request(method, url, headers, body, opts, state) do
    opts = Keyword.merge(state.default_opts, opts)
    finch_request = Finch.build(method, url, headers, body)

    Finch.request(finch_request, Goth.Finch, opts)
  end
end
