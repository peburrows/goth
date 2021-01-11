defmodule Goth.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    envs = Application.get_all_env(:goth)

    if envs == [] do
      Supervisor.start_link([], strategy: :one_for_one)
    else
      Goth.Supervisor.start_link(envs)
    end
  end
end
