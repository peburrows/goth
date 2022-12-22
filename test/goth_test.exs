defmodule GothTest do
  use ExUnit.Case

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

  test "lazily get default service account", %{test: test} do
    bypass = Bypass.open()
    now = System.system_time(:second)
    pid = self()
    url = "http://localhost:#{bypass.port}"

    # The test configuration sets an example JSON blob. We override it briefly
    # during this test.
    System.put_env("GOOGLE_APPLICATION_CREDENTIALS", "test/data/test-credentials-2.json")
    Application.stop(:goth)
    Application.start(:goth)

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    start_supervised!({Goth, name: test, source: {:default, url: url}})

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000

    {:ok, token} = Goth.fetch(test)
    assert token.token == "dummy"
    assert token.type == "Bearer"
    assert_in_delta token.expires, now + 3599, 1

    {:ok, ^token} = Goth.fetch(test)
    System.delete_env("GOOGLE_APPLICATION_CREDENTIALS")
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "lazily get default refresh token", %{test: test} do
    bypass = Bypass.open()
    now = System.system_time(:second)
    pid = self()
    url = "http://localhost:#{bypass.port}"

    System.put_env("GOOGLE_CLOUD_PROJECT", "test-project")
    current_json = Application.get_env(:goth, :json)
    root_dir = Application.get_env(:goth, :config_root_dir)
    Application.put_env(:goth, :json, nil, persistent: true)
    Application.put_env(:goth, :config_root_dir, "test/data/home/gcloud", persistent: true)
    Application.stop(:goth)
    Application.start(:goth)

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    start_supervised!({Goth, name: test, source: {:default, url: url}})

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000

    {:ok, token} = Goth.fetch(test)
    assert token.token == "dummy"
    assert token.type == "Bearer"
    assert_in_delta token.expires, now + 3599, 1

    {:ok, ^token} = Goth.fetch(test)
    System.delete_env("GOOGLE_CLOUD_PROJECT")
    Application.put_env(:goth, :json, current_json, persistent: true)
    Application.put_env(:goth, :config_root_dir, root_dir, persistent: true)
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "lazily get default metadata", %{test: test} do
    bypass = Bypass.open()
    now = System.system_time(:second)
    pid = self()
    url = "http://localhost:#{bypass.port}"

    # The test configuration sets an example JSON blob. We override it briefly
    # during this test.
    System.put_env("GOOGLE_CLOUD_PROJECT", "test-project")
    all_env = Application.get_all_env(:goth)
    Application.put_all_env([goth: [json: nil, config_root_dir: nil]], persistent: true)
    # Ensure the config root directory does not point to a SDK file.
    Application.put_env(:goth, :config_root_dir, "/test/data/home", persistent: true)
    Application.stop(:goth)
    Application.start(:goth)

    Bypass.stub(bypass, "GET", "/computeMetadata/v1/instance/service-accounts/default/token", fn conn ->
      send(pid, :pong)
      body = ~s|{"access_token":"dummy","expires_in":3599,"token_type":"Bearer"}|
      Plug.Conn.resp(conn, 200, body)
    end)

    start_supervised!({Goth, name: test, source: {:default, url: url}})

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000

    {:ok, token} = Goth.fetch(test)
    assert token.token == "dummy"
    assert token.type == "Bearer"
    assert_in_delta token.expires, now + 3599, 1

    {:ok, ^token} = Goth.fetch(test)

    # Restore original config
    System.delete_env("GOOGLE_CLOUD_PROJECT")
    Application.put_all_env([goth: all_env], persistent: true)
    Application.stop(:goth)
    Application.start(:goth)
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
  test "retries with default exp backoff", %{test: test} do
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
        max_retries: 3
      )

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 1000
    assert_receive :pong, 2000
    assert_receive :pong, 4000

    assert_receive {:EXIT, _, {%RuntimeError{message: "too many failed attempts to refresh" <> _}, _}},
                   8000
  end

  @tag :capture_log
  test "retries with custom backoff", %{test: test} do
    Process.flag(:trap_exit, true)
    pid = self()
    bypass = Bypass.open()

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      Plug.Conn.resp(conn, 500, "oops")
    end)

    fun = fn retry_count ->
      retry_count * 100
    end

    {:ok, _} =
      Goth.start_link(
        name: test,
        source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"},
        http_client: {:finch, []},
        max_retries: 3,
        retry_delay: fun
      )

    # higher timeouts since calculating JWT is expensive
    assert_receive :pong, 100
    assert_receive :pong, 200
    assert_receive :pong, 300

    assert_receive {:EXIT, _, {%RuntimeError{message: "too many failed attempts to refresh" <> _}, _}},
                   400
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

  test "force refresh if token is expired", %{test: test} do
    pid = self()
    bypass = Bypass.open()

    {:ok, agent} =
      Agent.start_link(fn ->
        [
          {200, ~s|{"access_token":#{System.unique_integer()},"expires_in":-1,"token_type":"Bearer"}|},
          {200, ~s|{"access_token":42,"expires_in":3599,"token_type":"Bearer"}|}
        ]
      end)

    Bypass.expect(bypass, fn conn ->
      send(pid, :pong)
      {status, body} = Agent.get_and_update(agent, fn [head | rest] -> {head, rest} end)
      Plug.Conn.resp(conn, status, body)
    end)

    config = [
      name: test,
      source: {:service_account, random_service_account_credentials(), url: "http://localhost:#{bypass.port}"},
      max_retries: 0,
      refresh_before: 1,
      refresh_before: -100
    ]

    start_supervised!({Goth, config})

    assert_receive :pong, 1000
    assert {:ok, %Goth.Token{token: 42}} = Goth.fetch(test)
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
