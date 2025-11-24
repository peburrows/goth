defmodule Goth.Token.ExAwsTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Goth.Token.ExAws

  describe "generate_subject_token/0" do
    test "generates a properly formatted subject token" do
      case ExAws.generate_subject_token() do
        {:ok, token} ->
          assert is_binary(token)
          decoded_token = Base.url_decode64!(token, padding: false)
          token_data = Jason.decode!(decoded_token)

          assert Map.has_key?(token_data, "url")
          assert Map.has_key?(token_data, "method")
          assert Map.has_key?(token_data, "headers")
          assert Map.has_key?(token_data, "body")

          assert token_data["method"] == "POST"

          url = token_data["url"]
          assert String.contains?(url, "sts")
          assert String.contains?(url, "GetCallerIdentity")

          headers = token_data["headers"]
          assert is_list(headers)

          Enum.each(headers, fn header ->
            assert Map.has_key?(header, "key")
            assert Map.has_key?(header, "value")
          end)

          auth_header = Enum.find(headers, fn h -> h["key"] == "authorization" end)
          assert auth_header != nil
          assert String.contains?(auth_header["value"], "AWS4-HMAC-SHA256")

          assert is_binary(token_data["body"])

        {:error, reason} when is_binary(reason) ->
          flunk("Expected success but got error: #{reason}")

        other ->
          flunk("Unexpected return value: #{inspect(other)}")
      end
    end
  end
end

