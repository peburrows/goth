defmodule Goth.TokenTest do
  use ExUnit.Case
  alias Goth.Token

  setup do
    bypass = Bypass.open()
    Application.put_env(:goth, :endpoint, "http://localhost:#{bypass.port}")
    Application.put_env(:goth, :token_source, :oauth)
    {:ok, bypass: bypass}
  end

  test "it can generate from response JSON" do
    json =
      ~s({"token_type":"Bearer","expires_in":3600,"access_token":"1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M"})

    assert %Token{
             token: "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
             type: "Bearer",
             expires: _exp
           } = Token.from_response_json("scope", json)
  end

  test "it can generate from response JSON with sub" do
    json =
      ~s({"token_type":"Bearer","expires_in":3600,"access_token":"1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M"})

    assert %Token{
             token: "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
             type: "Bearer",
             sub: "sub@example.com",
             expires: _exp,
             account: :default
           } = Token.from_response_json("scope", "sub@example.com", json)
  end

  test "it can generate from response JSON with sub and account" do
    json =
      ~s({"token_type":"Bearer","expires_in":3600,"access_token":"1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M"})

    assert %Token{
             token: "1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M",
             type: "Bearer",
             sub: "sub@example.com",
             expires: _exp,
             account: "account"
           } = Token.from_response_json({"account", "scope"}, "sub@example.com", json)
  end

  test "it calculates the expiration from the expires_in attr" do
    json =
      ~s({"token_type":"Bearer","expires_in":3600,"access_token":"1/8xbJqaOZXSUZbHLl5EOtu1pxz3fmmetKx9W8CV4t79M"})

    token = Token.from_response_json("my-scope", json)
    assert token.expires > :os.system_time(:seconds) + 3000
  end

  test "it will pull a token from the API the first time", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      Plug.Conn.resp(
        conn,
        201,
        Jason.encode!(%{"access_token" => "123", "token_type" => "Bearer", "expires_in" => 3600})
      )
    end)

    assert {:ok, %Token{token: "123", account: :default}} = Token.for_scope("random")

    assert {:ok, %Token{token: "123", account: :default}} =
             Token.for_scope("random", "sub@example.com")
  end

  test "it will not raise when token cannot be retrieved from the API" do
    orig = Application.get_env(:goth, :endpoint)
    Application.put_env(:goth, :endpoint, "http://lkjoine.lkj")
    assert {:error, _} = Token.for_scope("lkjlkjlkj")
    Application.put_env(:goth, :endpoint, orig)
  end

  test "it will pull a token for a specific account", %{bypass: bypass} do
    # The test configuration sets an example JSON blob. We override it briefly
    # during this test.
    current_json = Application.get_env(:goth, :json)
    new_json = "test/data/test-multicredentials.json" |> Path.expand() |> File.read!()

    Application.put_env(:goth, :json, new_json, persistent: true)
    Application.stop(:goth)

    Application.start(:goth)

    Bypass.expect(bypass, fn conn ->
      Plug.Conn.resp(
        conn,
        201,
        Jason.encode!(%{"access_token" => "123", "token_type" => "Bearer", "expires_in" => 3600})
      )
    end)

    assert {:ok,
            %Token{
              token: "123",
              account: "test-multicredentials-1@my-project.iam.gserviceaccount.com"
            }} =
             Token.for_scope(
               {"test-multicredentials-1@my-project.iam.gserviceaccount.com", "random"}
             )

    assert {:ok,
            %Token{
              token: "123",
              account: "test-multicredentials-1@my-project.iam.gserviceaccount.com"
            }} =
             Token.for_scope(
               {"test-multicredentials-1@my-project.iam.gserviceaccount.com", "random"},
               "sub@example.com"
             )

    # Restore original config
    Application.put_env(:goth, :json, current_json, persistent: true)
    System.delete_env("GOOGLE_APPLICATION_CREDENTIALS")
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "it will pull a token from the token store if cached", %{bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      Plug.Conn.resp(
        conn,
        201,
        Jason.encode!(%{"access_token" => "123", "token_type" => "Bearer", "expires_in" => 3600})
      )
    end)

    assert {:ok, %Token{token: access_token}} = Token.for_scope("another-random")
    assert access_token != nil

    Bypass.down(bypass)

    assert {:ok, %Token{token: ^access_token}} = Token.for_scope("another-random")
  end

  test "it will pull a token from the token store if cached when sub is provided", %{
    bypass: bypass
  } do
    {:ok, tries} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, fn conn ->
      Agent.update(tries, fn c -> c + 1 end)
      times = Agent.get(tries, fn c -> c end)

      resp =
        if times == 1 do
          %{"access_token" => "123", "token_type" => "Bearer", "expires_in" => 3600}
        else
          %{"access_token" => "123-sub", "token_type" => "Bearer", "expires_in" => 3600}
        end

      Plug.Conn.resp(
        conn,
        201,
        Jason.encode!(resp)
      )
    end)

    assert {:ok, %Token{token: access_token}} =
             Token.for_scope("another-random-sub", "sub@example.com")

    assert access_token != nil

    assert {:ok, %Token{token: ^access_token}} =
             Token.for_scope("another-random-sub", "sub@example.com")

    {:ok, %Token{token: access_token_2}} = Token.for_scope("another-random-sub")
    assert access_token != access_token_2
  end

  test "refreshing a token hits the API", %{bypass: bypass} do
    {:ok, tries} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, "POST", "/oauth2/v4/token", fn conn ->
      Agent.update(tries, fn c -> c + 1 end)
      times = Agent.get(tries, fn c -> c end)

      resp =
        if times == 1 do
          %{"access_token" => "123", "token_type" => "Bearer", "expires_in" => 3600}
        else
          %{"access_token" => "321", "token_type" => "Bearer", "expires_in" => 3600}
        end

      Plug.Conn.resp(
        conn,
        201,
        Jason.encode!(resp)
      )
    end)

    assert {:ok, token} = Token.for_scope("first")
    assert token.token != nil

    assert {:ok, %Token{token: at2}} = Token.refresh!(token)
    assert token.token != at2
  end
end
