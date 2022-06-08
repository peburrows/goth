defmodule Goth.Legacy.ClientTest do
  use ExUnit.Case
  alias Goth.Client
  alias Goth.Token

  setup do
    bypass = Bypass.open()
    bypass_url = "http://localhost:#{bypass.port}"
    Application.put_env(:goth, :endpoint, bypass_url)
    Application.put_env(:goth, :metadata_url, bypass_url)
    {:ok, bypass: bypass}
  end

  test "we include all necessary attributes in the JWT" do
    {:ok, email} = Goth.Config.get(:client_email)
    iat = :os.system_time(:seconds)
    exp = iat + 10
    scope = "prediction"

    assert %{
             "iss" => ^email,
             "scope" => ^scope,
             "aud" => "https://www.googleapis.com/oauth2/v4/token",
             "iat" => ^iat,
             "exp" => ^exp
           } = Client.claims(scope)
  end

  test "iat is support in the JWT" do
    {:ok, email} = Goth.Config.get(:client_email)
    iat = :os.system_time(:seconds) + 20
    exp = iat + 10
    scope = "prediction"

    token = %{
      "iss" => email,
      "scope" => scope,
      "aud" => "https://www.googleapis.com/oauth2/v4/token",
      "iat" => iat,
      "exp" => exp
    }

    assert token == Client.claims(scope, iat)
    assert token == Client.claims(scope, iat: iat)
  end

  test "sub is support in the JWT" do
    {:ok, email} = Goth.Config.get(:client_email)
    iat = :os.system_time(:seconds) + 30
    exp = iat + 10
    scope = "prediction"
    sub = "sub@example.com"

    assert %{
             "iss" => ^email,
             "scope" => ^scope,
             "aud" => "https://www.googleapis.com/oauth2/v4/token",
             "iat" => ^iat,
             "sub" => ^sub,
             "exp" => ^exp
           } = Client.claims(scope, iat: iat, sub: sub)
  end

  test "the claims json generated is legit" do
    json = Client.json("prediction")
    assert {:ok, _obj} = Jason.decode(json)
  end

  test "we call the API with the correct jwt data and generate a token", %{bypass: bypass} do
    token_response = %{
      "access_token" => "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
      "token_type" => "Bearer",
      "expires_in" => 3600
    }

    scope = "prediction"

    Bypass.expect(bypass, fn conn ->
      assert "/oauth2/v4/token" == conn.request_path
      assert "POST" == conn.method

      assert_body_is_legit_jwt(conn, scope)

      Plug.Conn.resp(conn, 201, Jason.encode!(token_response))
    end)

    {:ok, data} = Client.get_access_token(scope)

    at = token_response["access_token"]
    tt = token_response["token_type"]

    assert %Token{token: ^at, type: ^tt, expires: _exp} = data
  end

  defp assert_body_is_legit_jwt(conn, scope) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    assert String.length(body) > 0

    [_header, claims, _sign] = String.split(body, ".")
    claims = claims |> Base.url_decode64!(padding: false) |> Jason.decode!()

    generated = Client.claims(scope, claims["iat"])

    assert ^generated = claims
  end

  test "we call the API with the correct refresh data and generate a token", %{bypass: bypass} do
    token_response = %{
      "access_token" => "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
      "token_type" => "Bearer",
      "expires_in" => 3600
    }

    Bypass.stub(bypass, "GET", "/computeMetadata/v1/project/project-id", fn conn ->
      Plug.Conn.resp(conn, 200, "test-project")
    end)

    Bypass.stub(bypass, "POST", "/oauth2/v4/token", fn conn ->
      # assert "/oauth2/v4/token" == conn.request_path
      assert "POST" == conn.method

      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      assert body =~ ~r/refresh_token=refreshrefreshrefresh/

      Plug.Conn.resp(conn, 201, Jason.encode!(token_response))
    end)

    # Set up a temporary config with a refresh token
    normal_json = Application.get_env(:goth, :json)

    refresh_json =
      "test/data/home/gcloud/application_default_credentials.json"
      |> Path.expand()
      |> File.read!()

    Application.put_env(:goth, :json, refresh_json, persistent: true)
    Application.stop(:goth)
    Application.start(:goth)

    scope = "prediction"

    {:ok, data} = Client.get_access_token(scope)

    at = token_response["access_token"]
    tt = token_response["token_type"]

    assert %Token{token: ^at, type: ^tt, expires: _exp} = data

    # Restore original config
    Application.put_env(:goth, :json, normal_json, persistent: true)
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "We call the metadata service correctly and decode the token", %{bypass: bypass} do
    token_response = %{
      "access_token" => "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
      "token_type" => "Bearer",
      "expires_in" => 3600
    }

    scopes = [
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/taskqueue"
    ]

    scopes_response = Enum.join(scopes, "\n")

    Bypass.expect(bypass, fn conn ->
      url_t = "/computeMetadata/v1/instance/service-accounts/default/token"
      url_s = "/computeMetadata/v1/instance/service-accounts/default/scopes"

      assert(conn.method == "GET", "Request method should be GET")

      assert(
        Plug.Conn.get_req_header(conn, "metadata-flavor") == ["Google"],
        "Metadata header should be set correctly"
      )

      case conn.request_path do
        ^url_t -> Plug.Conn.resp(conn, 200, Jason.encode!(token_response))
        ^url_s -> Plug.Conn.resp(conn, 200, scopes_response)
      end
    end)

    {:ok, data} = Client.get_access_token(:metadata, Enum.join(scopes, " "))

    at = token_response["access_token"]
    tt = token_response["token_type"]

    assert(
      %Token{token: ^at, type: ^tt, expires: _exp} = data,
      "Returned token should match metadata response"
    )
  end

  test "When authentication fails, warn the user of the issue", %{bypass: bypass} do
    token_response = %{
      "error" => "deleted_client",
      "error_description" => "The OAuth client was deleted."
    }

    scope = "prediction"

    Bypass.expect(bypass, fn conn ->
      assert "/oauth2/v4/token" == conn.request_path
      assert "POST" == conn.method

      assert_body_is_legit_jwt(conn, scope)

      Plug.Conn.resp(conn, 401, Jason.encode!(token_response))
    end)

    {:error, data} = Client.get_access_token(scope)

    assert data =~ "Could not retrieve token, response:"
  end

  test "returns {:error, err} when HTTP call fails hard" do
    old_url = Application.get_env(:goth, :endpoint)
    Application.put_env(:goth, :endpoint, "https://nnnnnopelkjlkj.nope")
    assert {:error, _} = Client.get_access_token("my-scope")
    Application.put_env(:goth, :endpoint, old_url)
  end
end
