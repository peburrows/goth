defmodule GoogleAuth.TokenStoreTest do
  use ExUnit.Case
  alias GoogleAuth.TokenStore

  test "we can store an access token" do
    TokenStore.store("devstorage.readonly, prediction", "123", "Bearer", 100)
    {:ok, %{key: key, type: type, expires: exp}} = TokenStore.find("prediction")
    assert {"123", "Bearer"} = {key, type}
    assert exp <= 100
  end
end
