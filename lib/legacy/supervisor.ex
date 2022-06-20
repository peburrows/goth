defmodule Goth.Supervisor do
  @moduledoc false

  use Supervisor
  alias Goth.Config
  alias Goth.TokenStore

  def start_link(envs) do
    Supervisor.start_link(__MODULE__, envs, name: __MODULE__)
  end

  @impl true
  def init(envs) do
    children = [
      {Finch, name: Goth.Finch, pools: %{default: [protocol: :http1]}},
      {Config, envs},
      TokenStore,
      {Registry, keys: :unique, name: Goth.Registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
