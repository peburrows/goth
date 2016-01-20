defmodule GoogleAuth.ClientTest do
  use ExUnit.Case
  alias GoogleAuth.Client

  setup do
    bypass = Bypass.open
    Application.put_env(:google_auth, :endpoint, "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass}
  end

  test "we can generate a token", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      assert "/oauth2/v4/token" == conn.request_path
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, ~s<{"access_token" : "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M", "token_type" : "Bearer", "expires_in" : 3600}>)
    end

    {:ok, data} = Client.get_access_token("prediction")
    IO.inspect(data)
  end
end
