defmodule Goth.Supervisor do
  @moduledoc false

  use Supervisor
  alias Goth.Config
  alias Goth.TokenStore

  def start_link(envs) do
    Supervisor.start_link(__MODULE__, envs, name: __MODULE__)
  end

  def init(envs) do
    children = [
      {Config, envs},
      TokenStore
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
