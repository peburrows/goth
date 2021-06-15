defmodule Goth.TokenTest do
  use ExUnit.Case, async: true

  test "fetch/1 with service account" do
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
    assert token.scope == "https://www.googleapis.com/auth/cloud-platform"
  end

  test "fetch/1 with service account and impersonating user" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      body =
        ~s|{"access_token":"dummy","scope":"dummy_scope","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:service_account, random_service_account_credentials(),
          url: "http://localhost:#{bypass.port}",
          sub: "bob@example.com"}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == "https://www.googleapis.com/auth/cloud-platform"
    assert token.sub == "bob@example.com"
  end

  test "fetch/1 with service account and multiple scopes" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      body =
        ~s|{"access_token":"dummy","scope":"dummy_scope","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:service_account, random_service_account_credentials(),
         url: "http://localhost:#{bypass.port}", scopes: ["aaa", "bbb"]}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.scope == "aaa bbb"
  end

  test "fetch/1 with service account and OAuth ID token response" do
    bypass = Bypass.open()

    cloud_function_url = "https://europe-west1-project-id.cloudfunctions.net/test-function"

    jwk_es256 = JOSE.JWK.generate_key({:ec, :secp256r1})
    header = %{"alg" => "ES256", "typ" => "JWT"}

    payload = %{
      "aud" => cloud_function_url,
      "azp" => "example@project-id.iam.gserviceaccount.com",
      "email" => "example@project-id.iam.gserviceaccount.com",
      "email_verified" => true,
      "exp" => 1_623_761_103,
      "iat" => 1_623_757_503,
      "iss" => "https://accounts.google.com",
      "sub" => "110725120108142672649"
    }

    jwt =
      JOSE.JWS.sign(jwk_es256, Jason.encode!(payload), header) |> JOSE.JWS.compact() |> elem(1)

    Bypass.expect(bypass, fn conn ->
      body = ~s|{"id_token":"#{jwt}"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:service_account, random_service_account_credentials(),
         url: "http://localhost:#{bypass.port}", scopes: [cloud_function_url]}
    }

    assert {:ok,
            %{
              token: ^jwt,
              scope: ^cloud_function_url,
              expires: 1_623_761_103,
              type: "Bearer",
              sub: "110725120108142672649"
            }} = Goth.Token.fetch(config)
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
    {:error, error} = Goth.Token.fetch(config)
    assert error.message == ":econnrefused"
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
