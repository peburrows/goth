defmodule Goth.TokenTest do
  use ExUnit.Case, async: true

  test "fetch/1" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      body =
        ~s|{"access_token":"dummy","scope":"dummy_scope","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:service_account, random_service_account_credentials(),
         url: "http://localhost:#{bypass.port}"}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
  end

  test "fetch/1 with invalid response" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, fn conn ->
      body = ~s|bad|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:service_account, random_service_account_credentials(),
         url: "http://localhost:#{bypass.port}"}
    }

    {:error, %Jason.DecodeError{}} = Goth.Token.fetch(config)

    Bypass.down(bypass)
    {:error, :econnrefused} = Goth.Token.fetch(config)
  end

  test "fetch/1 with refresh token" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      body =
        ~s|{"access_token":"dummy","scope":"dummy_scope","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:refresh_token,
         %{"client_id" => "aaa", "client_secret" => "bbb", "refresh_token" => "ccc"},
         url: "http://localhost:#{bypass.port}"}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == "dummy_scope"
  end

  test "fetch/1 from instance metadata" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      assert conn.request_path == "/computeMetadata/v1/instance/service-accounts/alice/token"

      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source: {:metadata, account: "alice", url: "http://localhost:#{bypass.port}"}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == nil
  end

  defp random_service_account_credentials() do
    %{
      "private_key" => random_private_key(),
      "client_email" => "alice@example.com",
      "token_uri" => "/"
    }
  end

  defp random_private_key() do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    {:ok, private_key}
    :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])
  end
end
