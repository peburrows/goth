defmodule Goth.TokenStoreTest do
  use ExUnit.Case
  alias Goth.TokenStore
  alias Goth.Token

  setup do
    bypass = Bypass.open()
    Application.put_env(:goth, :endpoint, "http://localhost:#{bypass.port}")
    Application.put_env(:goth, :token_source, :oauth)
    {:ok, bypass: bypass}
  end

  test "we can store an access token" do
    TokenStore.store("devstorage.readonly, prediction", %Token{
      token: "123",
      type: "Bearer",
      expires: :os.system_time(:seconds) + 1000
    })

    {:ok, token} = TokenStore.find("devstorage.readonly, prediction")
    assert %Token{token: "123", type: "Bearer"} = token
    assert token.expires > :os.system_time(:seconds) + 900
  end

  test "we can store an acces token for a specific account" do
    TokenStore.store({"account@example.com", "devstorage.readonly, prediction"}, %Token{
      token: "123",
      type: "Bearer",
      expires: :os.system_time(:seconds) + 1000,
      account: "account@example.com"
    })

    {:ok, token} = TokenStore.find({"account@example.com", "devstorage.readonly, prediction"})
    assert %Token{token: "123", type: "Bearer"} = token
    assert token.expires > :os.system_time(:seconds) + 900
  end

  test "a token is queued for refresh when stored" do
    token = %Token{
      scope: "will-be-stale",
      token: "stale",
      type: "Bearer",
      sub: "sub@example.com",
      expires: :os.system_time(:seconds) + 1000,
      account: :default
    }

    # if queued for later, we'll get back a reference
    {:ok, {_id, ref}} = TokenStore.store(token)
    assert is_reference(ref)
  end

  test "an expired token is refreshed immediately", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      Plug.Conn.resp(
        conn,
        201,
        Poison.encode!(%{
          "access_token" => "fresh",
          "token_type" => "Bearer",
          "expires_in" => 3600
        })
      )
    end)

    token = %Token{
      scope: "refresh-me",
      token: "stale",
      type: "Bearer",
      expires: 1,
      account: :default
    }

    task = TokenStore.store(token)
    ref = Process.monitor(task.pid)
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 1000
    assert {:ok, %Token{token: "fresh"}} = TokenStore.find("refresh-me")
  end

  # Edge case, should be refreshed automatically but on dev machines
  # which go to sleep, it is not always happeneing
  test "find never returns stale tokens", %{bypass: _bypass} do
    token = %Token{scope: "expired", token: "stale", type: "Bearer", expires: 1}
    {:ok, _pid} = GenServer.start_link(Goth.TokenStore, %{"expired" => token})
    assert :error = TokenStore.find("expired")
  end

  test "token can be stored with sub" do
    sub = "sub@example.com"

    TokenStore.store("devstorage.readonly, prediction", %Token{
      token: "123",
      type: "Bearer",
      sub: sub,
      expires: :os.system_time(:seconds) + 1000
    })

    {:ok, token} = TokenStore.find("devstorage.readonly, prediction", sub)
    assert %Token{token: "123", type: "Bearer", sub: _} = token
    assert token.expires > :os.system_time(:seconds) + 900
  end

  test "tokens with the same scope but different sub are stored seperately" do
    scopes = "devstorage.readonly, prediction, drive.readonly"
    sub1 = "sub1@example.com"
    sub2 = "sub2@example.com"

    TokenStore.store(scopes, %Token{
      token: "123",
      type: "Bearer",
      sub: sub1,
      expires: :os.system_time(:seconds) + 1000,
      account: :default
    })

    TokenStore.store(scopes, %Token{
      token: "123",
      type: "Bearer",
      sub: sub2,
      expires: :os.system_time(:seconds) + 1000,
      account: :default
    })

    assert :error == TokenStore.find(scopes)
    {:ok, token1} = TokenStore.find(scopes, sub1)
    {:ok, token2} = TokenStore.find(scopes, sub2)
    assert token1 != token2
  end

  test "tokens with same scopes and subs but with different accounts are stored separately" do
    scopes = "helloworld"
    sub = "person@example.com"
    account1 = "account1@example.com"
    account2 = "account2@example.com"

    TokenStore.store({account1, scopes}, %Token{
      token: "123",
      type: "Bearer",
      sub: sub,
      expires: :os.system_time(:seconds) + 1000,
      account: account1
    })

    TokenStore.store({account2, scopes}, %Token{
      token: "123",
      type: "Bearer",
      sub: sub,
      expires: :os.system_time(:seconds) + 1000,
      account: account2
    })

    assert :error == TokenStore.find(scopes, sub)
    {:ok, %Token{account: ^account1} = token1} = TokenStore.find({account1, scopes}, sub)
    {:ok, %Token{account: ^account2} = token2} = TokenStore.find({account2, scopes}, sub)
    assert token1 != token2
  end
end
