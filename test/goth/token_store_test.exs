defmodule Goth.TokenStoreTest do
  use ExUnit.Case
  alias Goth.TokenStore
  alias Goth.Token

  setup do
    bypass = Bypass.open
    Application.put_env(:goth, :endpoint, "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass}
  end

  test "we can store an access token" do
    TokenStore.store("devstorage.readonly, prediction", %Token{token: "123", type: "Bearer", expires: :os.system_time(:seconds)+1000})
    {:ok, token} = TokenStore.find("devstorage.readonly, prediction")
    assert %Token{token: "123", type: "Bearer"} = token
    assert token.expires > :os.system_time(:seconds) + 900
  end

  test "a token is queued for refresh when stored", %{bypass: bypass} do
    token = %Token{scope: "will-be-stale", token: "stale", type: "Bearer", expires: :os.system_time(:seconds)+1000}

    # if queued for later, we'll get back a reference
    {:ok, {_id, ref}} = TokenStore.store(token)
    assert is_reference(ref)
  end

  test "an expired token is refreshed immediately", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 201, Poison.encode!(%{"access_token" => "fresh", "token_type" => "Bearer", "expires_in" => 3600}))
    end

    token = %Token{scope: "refresh-me", token: "stale", type: "Bearer", expires: 1}
    task = TokenStore.store(token)
    ref  = Process.monitor(task.pid)
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 1000
    assert {:ok, %Token{token: "fresh"}} = TokenStore.find("refresh-me")
  end
end
