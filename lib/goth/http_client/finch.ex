defmodule Goth.HTTPClient.Finch do
  @moduledoc false
  @behaviour Goth.HTTPClient

  defstruct default_opts: []

  require Logger

  @impl true
  def init(opts) do
    struct!(__MODULE__, opts)
  end

  @impl true
  def request(method, url, headers, body, opts, state) do
    opts = Keyword.merge(state.default_opts, opts)
    finch_request = Finch.build(method, url, headers, body)

    Finch.request(finch_request, Goth.Finch, opts)
  end
end
