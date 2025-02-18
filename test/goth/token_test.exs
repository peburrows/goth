defmodule Goth.TokenTest do
  use ExUnit.Case, async: true

  @default_scope "https://www.googleapis.com/auth/cloud-platform"

  test "fetch/1 with service account" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      assert %{
               "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
               "assertion" => assertion
             } = fetch_request_body(conn)

      assert %{
               "aud" => "https://www.googleapis.com/oauth2/v4/token",
               "iss" => "alice@example.com",
               "scope" => @default_scope
             } = jwt_decode(assertion)

      body = ~s|{"access_token":"dummy","scope":"#{@default_scope}","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == @default_scope
    assert token.sub == nil
  end

  test "fetch/1 with service account and impersonating user" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      assert %{
               "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
               "assertion" => assertion
             } = fetch_request_body(conn)

      assert %{
               "iss" => "alice@example.com",
               "scope" => @default_scope,
               "sub" => "bob@example.com"
             } = jwt_decode(assertion)

      body = ~s|{"access_token":"dummy","scope":"#{@default_scope}","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    creds = random_service_account_credentials()
    bypass_url = "http://localhost:#{bypass.port}"
    claims = %{"sub" => "bob@example.com", "scope" => @default_scope}
    service_account_source = {:service_account, creds, url: bypass_url, claims: claims}

    {:ok, token} = Goth.Token.fetch(%{source: service_account_source})
    assert token.token == "dummy"
    assert token.scope == @default_scope
    assert token.sub == "bob@example.com"
  end

  test "fetch/1 with service account and multiple scopes" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      assert %{
               "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
               "assertion" => assertion
             } = fetch_request_body(conn)

      assert %{"scope" => "aaa bbb"} = jwt_decode(assertion)

      body = ~s|{"access_token":"dummy","scope":"aaa bbb","expires_in":3599,"token_type":"Bearer"}|

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

    jwt = JOSE.JWS.sign(jwk_es256, Jason.encode!(payload), header) |> JOSE.JWS.compact() |> elem(1)

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
      source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"}
    }

    {:error, %Jason.DecodeError{}} = Goth.Token.fetch(config)

    Bypass.down(bypass)
    {:error, error} = Goth.Token.fetch(config)
    assert error.reason == :econnrefused
  end

  test "fetch/1 with refresh token" do
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      body = ~s|{"access_token":"dummy","scope":"dummy_scope","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    config = %{
      source:
        {:refresh_token, %{"client_id" => "aaa", "client_secret" => "bbb", "refresh_token" => "ccc"},
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

  test "fetch/1 from workload identity" do
    token_bypass = Bypass.open()
    sa_token_bypass = Bypass.open()

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    Bypass.expect(sa_token_bypass, fn conn ->
      assert conn.request_path ==
               "/v1/projects/-/serviceAccounts/test-credentials-workload-identity@my-project.iam.gserviceaccount.com:generateAccessToken"

      body = ~s|{"accessToken":"dummy_sa","expireTime":"2024-06-30T00:00:00Z"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-workload-identity.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")
      |> Map.put(
        "service_account_impersonation_url",
        "http://localhost:#{sa_token_bypass.port}/v1/projects/-/serviceAccounts/test-credentials-workload-identity@my-project.iam.gserviceaccount.com:generateAccessToken"
      )

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy_sa"
    assert token.scope == @default_scope
  end

  test "fetch/1 from workload identity and multiple scopes" do
    token_bypass = Bypass.open()
    sa_token_bypass = Bypass.open()

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      assert %{
               "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
               "scope" => "aaa bbb"
             } = fetch_request_body(conn)

      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    Bypass.expect(sa_token_bypass, fn conn ->
      assert conn.request_path ==
               "/v1/projects/-/serviceAccounts/test-credentials-workload-identity@my-project.iam.gserviceaccount.com:generateAccessToken"

      body = ~s|{"accessToken":"dummy_sa","expireTime":"2024-06-30T00:00:00Z"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-workload-identity.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")
      |> Map.put(
        "service_account_impersonation_url",
        "http://localhost:#{sa_token_bypass.port}/v1/projects/-/serviceAccounts/test-credentials-workload-identity@my-project.iam.gserviceaccount.com:generateAccessToken"
      )

    config = %{
      source: {:workload_identity, credentials, scopes: ["aaa", "bbb"]}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy_sa"
    assert token.scope == "aaa bbb"
  end

  test "fetch/1 from direct workload identity" do
    token_bypass = Bypass.open()

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-direct-workload-identity.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == @default_scope
  end

  test "fetch/1 from direct workload identity, json format" do
    token_bypass = Bypass.open()

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-direct-workload-identity-json.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == @default_scope
  end

  test "fetch/1 from url-based workload identity" do
    token_bypass = Bypass.open()
    subject_token_bypass = Bypass.open()

    Bypass.expect(subject_token_bypass, fn conn ->
      assert conn.request_path == "/get/credentials"

      body = File.read!("test/data/workload-identity-token.json")
      Plug.Conn.resp(conn, 200, body)
    end)

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      body = ~s|{"access_token":"dummy","expires_in":599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-url-workload-identity.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")
      |> Map.update!("credential_source", fn source ->
        Map.put(source, "url", "http://localhost:#{subject_token_bypass.port}/get/credentials")
      end)

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == @default_scope
  end

  test "fetch/1 with AWS workload identity" do
    access_key_id = "ASIAXXXXXXXXXXXXXXXXXX"
    secret_access_key = "oXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    token = "oXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

    metadata_region_bypass = Bypass.open()
    metadata_credentials_bypass = Bypass.open()
    sts_bypass = Bypass.open()
    token_bypass = Bypass.open()

    Bypass.expect(metadata_region_bypass, fn conn ->
      assert conn.request_path == "/latest/meta-data/placement/availability-zone"
      Plug.Conn.resp(conn, 200, "us-east-1a")
    end)

    Bypass.expect(metadata_credentials_bypass, fn conn ->
      assert conn.request_path == "/latest/meta-data/iam/security-credentials/"
      Plug.Conn.resp(conn, 200, "test-role")
    end)

    Bypass.expect(metadata_credentials_bypass, "GET", "/latest/meta-data/iam/security-credentials/test-role", fn conn ->
      body = ~s|
      {
        "Code": "Success",
        "LastUpdated": "2023-10-26T21:31:48Z",
        "Type": "AWS-HMAC",
        "AccessKeyId": "#{access_key_id}",
        "SecretAccessKey": "#{secret_access_key}",
        "Token": "#{token}",
        "Expiration": "2023-10-27T00:01:01Z"
      }
      |
      Plug.Conn.resp(conn, 200, body)
    end)

    Bypass.expect(token_bypass, fn conn ->
      assert conn.request_path == "/v1/token"

      req_body = conn |> Plug.Conn.read_body() |> elem(1)
      params = URI.decode_query(req_body)
      subject_token = params["subject_token"]
      audience = params["audience"]

      aws_conf =
        ExAws.Config.new(:sts,
          access_key_id: access_key_id,
          secret_access_key: secret_access_key,
          security_token: token,
          region: "us-east-1"
        )

      regional_cred_verification_url =
        "http://localhost:#{sts_bypass.port}/?Action=GetCallerIdentity&Version=2011-06-15"

      {:ok, expected_headers} =
        ExAws.Auth.headers(
          :post,
          regional_cred_verification_url,
          :sts,
          aws_conf,
          [{"x-goog-cloud-target-resource", audience}],
          ""
        )

      decoded_request = URI.decode(subject_token) |> Jason.decode!()
      request_headers = for %{"key" => k, "value" => v} <- decoded_request["headers"], into: %{}, do: {k, v}

      Enum.each(expected_headers, fn {key, value} ->
        assert Map.get(request_headers, key) == value
      end)

      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|

      Plug.Conn.resp(conn, 200, body)
    end)

    credentials =
      File.read!("test/data/test-credentials-aws-workload-identity.json")
      |> Jason.decode!()
      |> Map.put("token_url", "http://localhost:#{token_bypass.port}/v1/token")
      |> Map.update!("credential_source", fn source ->
        source
        |> Map.put(
          "region_url",
          "http://localhost:#{metadata_region_bypass.port}/latest/meta-data/placement/availability-zone"
        )
        |> Map.put(
          "url",
          "http://localhost:#{metadata_credentials_bypass.port}/latest/meta-data/iam/security-credentials"
        )
        |> Map.put(
          "regional_cred_verification_url",
          "http://localhost:#{sts_bypass.port}/?Action=GetCallerIdentity&Version=2011-06-15"
        )
      end)

    config = %{
      source: {:workload_identity, credentials}
    }

    {:ok, token} = Goth.Token.fetch(config)
    assert token.token == "dummy"
    assert token.scope == @default_scope
  end

  defp random_service_account_credentials do
    %{
      "private_key" => random_private_key(),
      "client_email" => "alice@example.com",
      "token_uri" => "/"
    }
  end

  defp random_private_key do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    {:ok, private_key}
    :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])
  end

  defp fetch_request_body(%Plug.Conn{} = conn) do
    assert {:ok, req_body, _} = Plug.Conn.read_body(conn)
    URI.decode_query(req_body)
  end

  def jwt_decode(jwt) when is_binary(jwt), do: jwt |> JOSE.JWT.peek_payload() |> Map.get(:fields)
end
