defmodule GoogleAuth do
  use Supervisor
  alias GoogleAuth.Config

  # for now, just spin up the supervisor
  def start(_type, _args) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    children = [
      worker(Config, [%{}, [name: :auth_config]])
    ]

    supervise(children, strategy: :one_for_one)
  end

  def set(key, value) do
    Config.set(:auth_config, key, value)
  end

  def get(key) do
    Config.get(:auth_config, key)
  end
end
