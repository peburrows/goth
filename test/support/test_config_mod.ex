defmodule Goth.TestConfigMod do
  @moduledoc false

  use Goth.Config

  def init(config) do
    {:ok, Keyword.put(config, :actor_email, :val)}
  end
end
