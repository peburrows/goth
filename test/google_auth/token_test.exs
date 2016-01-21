defmodule GoogleAuth.TokenTest do
  use ExUnit.Case
  alias GoogleAuth.Token

  setup do
    bypass = Bypass.open
    Application.put_env(:google_auth, :endpoint, "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass}
  end

  test "it can generate from response JSON" do
    json = ~s({"token_type":"Bearer","expires_in":3600,"access_token":"1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M"})
    assert %Token{
      token: "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
      type: "Bearer",
      expires: 3600
    } = Token.from_response_json(json)
  end

  test "it will pull a token from the API the first time", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 201, Poison.encode!(%{"access_token" => "123", "token_type" => "Bearer", "expires_in" => 100}))
    end

     assert {:ok, %Token{token: "123"}} = Token.for_scope("random")
  end

  test "it will pull a token from the token store if cached", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 201, Poison.encode!(%{"access_token" => "123", "token_type" => "Bearer", "expires_in" => 100}))
    end

    assert {:ok, %Token{token: access_token}} = Token.for_scope("another-random")
    assert access_token != nil

    Bypass.down(bypass)

    assert {:ok, %Token{token: ^access_token}} = Token.for_scope("another-random")
  end
end
