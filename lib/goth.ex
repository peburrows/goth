defmodule Goth do
  use Application

  # for now, just spin up the supervisor
  def start(_type, _args) do
    Goth.Supervisor.start_link
  end
end
