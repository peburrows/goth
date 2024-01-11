defmodule Goth.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Goth.Registry},
      {Finch, name: Goth.Finch, pools: %{default: finch_default_pool_opts()}},
      Goth.TokenStore
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Goth.Supervisor)
  end

  defp finch_default_pool_opts do
    finch_version = Application.spec(:finch, :vsn)

    if Version.match?(List.to_string(finch_version), ">= 0.17.0") do
      [protocols: [:http1]]
    else
      [protocol: :http1]
    end
  end
end
