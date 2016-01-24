defmodule Goth do
  use Application

  @moduledoc """
  Google + Auth = Goth.
  """

  # for now, just spin up the supervisor
  def start(_type, _args) do
    Goth.Supervisor.start_link
  end
end
