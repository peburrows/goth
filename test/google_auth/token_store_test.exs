defmodule GoogleAuth.TokenStoreTest do
  use ExUnit.Case
  alias GoogleAuth.TokenStore
  alias GoogleAuth.Token

  test "we can store an access token" do
    TokenStore.store("devstorage.readonly, prediction", %Token{token: "123", type: "Bearer", expires: 100})
    {:ok, token} = TokenStore.find("devstorage.readonly, prediction")
    assert %Token{token: "123", type: "Bearer"} = token
    assert token.expires <= 100
  end
end
