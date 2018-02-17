defmodule Goth.TestConfigMod do
  use Goth.Config

  def init(config) do
    {:ok, Keyword.put(config, :actor_email, :val)}
  end
end
