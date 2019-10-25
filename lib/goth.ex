defmodule Goth do
  use Application

  @moduledoc """
  Google + Auth = Goth.
  """

  # for now, just spin up the supervisor
  def start(_type, _args) do
    envs = Application.get_all_env(:goth)
    Goth.Supervisor.start_link(envs)
  end
end
