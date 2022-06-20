defmodule GothTest do
  use ExUnit.Case, async: true

  test "fetch/1", %{test: test} do
    now = System.system_time(:second)
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = [
      name: test,
      source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"}
    ]

    start_supervised!({Goth, config})

    {:ok, token} = Goth.fetch(test)
    assert token.token == "dummy"
    assert token.type == "Bearer"
    assert_in_delta token.expires, now + 3599, 1

    Bypass.down(bypass)
    {:ok, ^token} = Goth.fetch(test)
  end

  test "sync prefetch", %{test: test} do
    now = System.system_time(:second)
    bypass = Bypass.open()
    pid = self()

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = [
      name: test,
      source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"},
      prefetch: :sync
    ]

    start_supervised!({Goth, config})

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000

    {:ok, token} = Goth.fetch(test)
    assert token.token == "dummy"
    assert token.type == "Bearer"
    assert_in_delta token.expires, now + 3599, 1

    Bypass.down(bypass)
    {:ok, ^token} = Goth.fetch(test)
  end

  test "custom http client", %{test: test} do
    now = System.system_time(:second)

    config = [
      name: test,
      source: {:service_account, random_service_account_credentials(), []},
      http_client: &http_client/1
    ]

    start_supervised!({Goth, config})

    assert {:ok, token} = Goth.fetch(test)

    assert token.token == "dummy"
    assert token.type == "Bearer"
    assert_in_delta token.expires, now + 3599, 1

    assert {:ok, ^token} = Goth.fetch(test)
  end

  test "custom http client with options", %{test: test} do
    now = System.system_time(:second)

    config = [
      name: test,
      source: {:service_account, random_service_account_credentials(), []},
      http_client: {&http_client_with_options/1, [test: test]}
    ]

    start_supervised!({Goth, config})

    assert {:ok, token} = Goth.fetch(test)

    assert token.token == "dummy"
    assert token.type == "Bearer"
    assert_in_delta token.expires, now + 3599, 1

    assert {:ok, ^token} = Goth.fetch(test)
  end

  @tag :capture_log
  test "http client with already decoded body", %{test: test} do
    now = System.system_time(:second)

    config = [
      name: test,
      source: {:service_account, random_service_account_credentials(), []},
      http_client: &http_client_with_decoded_body/1
    ]

    start_supervised!({Goth, config})

    assert {:ok, token} = Goth.fetch(test)

    assert token.token == "dummy"
    assert token.type == "Bearer"
    assert_in_delta token.expires, now + 3599, 1

    assert {:ok, ^token} = Goth.fetch(test)
  end

  @tag :capture_log
  test "retries with rand backoff", %{test: test} do
    Process.flag(:trap_exit, true)
    pid = self()
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      Plug.Conn.resp(conn, 500, "oops")
    end)

    {:ok, _} =
      Goth.start_link(
        name: test,
        source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"},
        http_client: {:finch, []},
        max_retries: 3,
        backoff_type: :rand,
        backoff_min: 1,
        backoff_max: 1_000
      )

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000
    assert_receive :pong, 1000
    assert_receive :pong, 1000

    assert_receive {:EXIT, _, {%RuntimeError{message: "too many failed attempts to refresh" <> _}, _}},
                   1000
  end

  @tag :capture_log
  test "retries with exp backoff", %{test: test} do
    Process.flag(:trap_exit, true)
    pid = self()
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      Plug.Conn.resp(conn, 500, "oops")
    end)

    {:ok, _} =
      Goth.start_link(
        name: test,
        source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"},
        http_client: {:finch, []},
        max_retries: 3,
        backoff_type: :exp,
        backoff_min: 1,
        backoff_max: 1_000
      )

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000
    assert_receive :pong, 1000
    assert_receive :pong, 1000

    assert_receive {:EXIT, _, {%RuntimeError{message: "too many failed attempts to refresh" <> _}, _}},
                   1000
  end

  @tag :capture_log
  test "retries with rand_exp backoff", %{test: test} do
    Process.flag(:trap_exit, true)
    pid = self()
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      Plug.Conn.resp(conn, 500, "oops")
    end)

    {:ok, _} =
      Goth.start_link(
        name: test,
        source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"},
        http_client: {:finch, []},
        max_retries: 3,
        backoff_type: :rand_exp,
        backoff_min: 1,
        backoff_max: 1_000
      )

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000
    assert_receive :pong, 1000
    assert_receive :pong, 1000

    assert_receive {:EXIT, _, {%RuntimeError{message: "too many failed attempts to refresh" <> _}, _}},
                   1000
  end

  test "refresh", %{test: test} do
    pid = self()
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      body = ~s|{"access_token":#{System.unique_integer()},"expires_in":1,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    config = [
      name: test,
      source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"},
      max_retries: 0,
      refresh_before: 1
    ]

    start_supervised!({Goth, config})

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000
    assert_receive :pong, 1000
    assert_receive :pong, 1000
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

  defp http_client(options) do
    validate_options(options)

    {:ok,
     %{
       status: 200,
       body: ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
     }}
  end

  defp http_client_with_options(options) do
    validate_options(options)

    assert Keyword.has_key?(options, :test)
    assert options[:test] === :"test custom http client with options"

    {:ok,
     %{
       status: 200,
       body: ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
     }}
  end

  defp http_client_with_decoded_body(options) do
    validate_options(options)

    {:ok,
     %{
       status: 200,
       body: %{"access_token" => "dummy", "expires_in" => 3599, "token_type" => "Bearer"}
     }}
  end

  defp validate_options(options) do
    assert Keyword.has_key?(options, :method)
    assert Keyword.has_key?(options, :url)
    assert Keyword.has_key?(options, :headers)
    assert Keyword.has_key?(options, :body)
  end
end
