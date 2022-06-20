defmodule Goth.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    envs = Application.get_all_env(:goth)

    if envs == [] do
      children = [
        {Registry, keys: :unique, name: Goth.Registry},
        {Finch, name: Goth.Finch, pools: %{default: [protocol: :http1]}}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
    else
      Goth.Supervisor.start_link(envs)
    end
  end
end
