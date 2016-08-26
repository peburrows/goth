defmodule Goth.Supervisor do
  @moduledoc false

  use Supervisor
  alias Goth.Config
  alias Goth.TokenStore

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
    # Supervisor.start_link(__MODULE__, [])
  end

  def init(:ok) do
    children = [
      worker(Config, []),
      worker(TokenStore, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
