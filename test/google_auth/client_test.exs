defmodule GoogleAuth.ClientTest do
  use ExUnit.Case
  alias GoogleAuth.Client
  alias GoogleAuth.Token

  setup do
    bypass = Bypass.open
    Application.put_env(:google_auth, :endpoint, "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass}
  end

  test "we include all necessary attributes in the JWT" do
    {:ok, email} = GoogleAuth.Config.get(:client_email)
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

    token = %Token{token: token_response["access_token"], type: token_response["token_type"], expires: token_response["expires_in"]}

    assert ^token = data
  end

  defp assert_body_is_legit_jwt(conn, scope) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    assert String.length(body) > 0

    [_header, claims, _sign] = String.split(body, ".")
    claims = claims |> JsonWebToken.Format.Base64Url.decode |> Poison.decode!

    generated = Client.claims(scope, claims["iat"])

    assert ^generated = claims
  end
end
