defmodule GoogleAuth.TokenTest do
  use ExUnit.Case
  alias GoogleAuth.Token

  test "it can generate from response JSON" do
    json = ~s({"token_type":"Bearer","expires_in":3600,"access_token":"1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M"})
    assert %Token{
      token: "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
      type: "Bearer",
      expires: 3600
    } = Token.from_response_json(json)
  end
end
