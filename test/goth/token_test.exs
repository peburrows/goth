defmodule Goth.TokenTest do
  use ExUnit.Case, async: true

  test "fetch/1" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      credentials: random_credentials(),
      url: "http://localhost:#{bypass.port}",
      scope: "https://www.googleapis.com/auth/cloud-platform"
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
      credentials: random_credentials(),
      url: "http://localhost:#{bypass.port}",
      scope: "https://www.googleapis.com/auth/cloud-platform"
    }

    {:error, %Jason.DecodeError{}} = Goth.Token.fetch(config)

    Bypass.down(bypass)
    {:error, :econnrefused} = Goth.Token.fetch(config)
  end

  test "fetch/1 from instance metadata" do
    bypass = Bypass.open()
    pid = self()

    Bypass.expect(bypass, fn conn ->
      send(pid, {:token_requested, conn.request_path, conn.query_string})
      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      credentials: {:instance, "default"},
      url: "http://localhost:#{bypass.port}"
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == ""

    assert_received {:token_requested, "/service-accounts/default/token", ""}
  end

  test "fetch/1 from instance metadata with scope" do
    bypass = Bypass.open()
    pid = self()

    Bypass.expect(bypass, fn conn ->
      send(pid, {:token_requested, conn.request_path, conn.query_string})
      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      credentials: {:instance, "12345-user@iam.example.com"},
      url: "http://localhost:#{bypass.port}",
      scope: "https://www.googleapis.com/auth/pubsub"
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"

    assert_received {:token_requested, "/service-accounts/12345-user@iam.example.com/token",
                     "scopes=https://www.googleapis.com/auth/pubsub"}
  end

  defp random_credentials() do
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
