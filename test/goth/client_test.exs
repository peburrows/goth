defmodule Goth.ClientTest do
  use ExUnit.Case
  alias Goth.Client
  alias Goth.Token

  setup do
    bypass = Bypass.open
    bypass_url = "http://localhost:#{bypass.port}"
    Application.put_env(:goth, :endpoint, bypass_url)
    Application.put_env(:goth, :metadata_url, bypass_url)
    {:ok, bypass: bypass}
  end

  test "we include all necessary attributes in the JWT" do
    {:ok, email} = Goth.Config.get(:client_email)
    iat = :os.system_time(:seconds)
    exp = iat+10
    scope = "prediction"

    assert %{
      "iss"   => ^email,
      "scope" => ^scope,
      "aud"   => "https://www.googleapis.com/oauth2/v4/token",
      "iat"   => ^iat,
      "exp"   =>   ^exp
    } = Client.claims(scope)
  end

  test "the claims json generated is legit" do
    json = Client.json("prediction")
    assert {:ok, _obj} = Poison.decode(json)
  end

  test "we call the API with the correct data and generate a token", %{bypass: bypass} do
    token_response = %{
      "access_token" => "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
      "token_type"   => "Bearer",
      "expires_in"   => 3600
    }

    scope = "prediction"

    Bypass.expect bypass, fn conn ->
      assert "/oauth2/v4/token" == conn.request_path
      assert "POST"             == conn.method

      assert_body_is_legit_jwt(conn, scope)

      Plug.Conn.resp(conn, 201, Poison.encode!(token_response))
    end

    {:ok, data} = Client.get_access_token(scope)

    at = token_response["access_token"]
    tt = token_response["token_type"]
    
    assert %Token{token: ^at, type: ^tt, expires: _exp} = data
  end

  defp assert_body_is_legit_jwt(conn, scope) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    assert String.length(body) > 0

    [_header, claims, _sign] = String.split(body, ".")
    claims = claims |> JsonWebToken.Format.Base64Url.decode |> Poison.decode!

    generated = Client.claims(scope, claims["iat"])

    assert ^generated = claims
  end

  test "We call the metadata service correctly and decode the token", %{bypass: bypass} do
    token_response = %{
      "access_token" => "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
      "token_type"   => "Bearer",
      "expires_in"   => 3600
    }

    scopes = ["https://www.googleapis.com/auth/pubsub",
              "https://www.googleapis.com/auth/taskqueue"]
    scopes_response = Enum.join(scopes, "\n")

    Bypass.expect(bypass, fn(conn) ->
      url_t = "/computeMetadata/v1/instance/service-accounts/default/token"
      url_s = "/computeMetadata/v1/instance/service-accounts/default/scopes"

      assert(conn.method == "GET", "Request method should be GET")
      assert(Plug.Conn.get_req_header(conn, "metadata-flavor") == ["Google"],
             "Metadata header should be set correctly")

      case conn.request_path do
        ^url_t -> Plug.Conn.resp(conn, 200, Poison.encode!(token_response))
        ^url_s -> Plug.Conn.resp(conn, 200, scopes_response)
      end
    end)

    {:ok, data} = Client.get_access_token(:metadata, Enum.join(scopes, " "))

    at = token_response["access_token"]
    tt = token_response["token_type"]

    assert(%Token{token: ^at, type: ^tt, expires: _exp} = data,
           "Returned token should match metadata response")
  end
end
