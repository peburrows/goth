defmodule Goth.Supervisor do
  @moduledoc false

  use Supervisor
  alias Goth.TokenStore

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Finch, name: Goth.Finch, pools: %{default: [protocol: :http1]}},
      TokenStore,
      {Registry, keys: :unique, name: Goth.Registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
