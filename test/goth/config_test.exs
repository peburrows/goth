defmodule Goth.ConfigTest do
  use ExUnit.Case
  alias Goth.Config

  setup do
    bypass = Bypass.open
    bypass_url = "http://localhost:#{bypass.port}"
    Application.put_env(:goth, :metadata_url, bypass_url)
    {:ok, bypass: bypass}
  end

  test "setting and retrieving value" do
    Config.set(:key, "123")
    assert {:ok, "123"} == Config.get(:key)
  end

  test "setting a value by atom can be retrieved by string" do
    Config.set(:random, "value")
    assert {:ok, "value"} == Config.get("random")
  end

  test "setting a value by string can be retrieved by atom" do
    Config.set("totally", "cool")
    assert {:ok, "cool"} == Config.get(:totally)
  end

  test "the initial state is what's passed in from the app config" do
    state = "config/test-credentials.json" |> Path.expand |> File.read! |> Poison.decode!
    state |> Map.keys |> Enum.each(fn(key) ->
      assert {:ok, state[key]} == Config.get(key)
    end)
  end

  test "the initial state has the token_source set to oauth" do
    assert {:ok, :oauth} == Config.get(:token_source)
  end

  test "Goth correctly retrieves project IDs from metadata", %{bypass: bypass} do
    # The test configuration sets an example JSON blob. We override it briefly
    # during this test.
    current_json = Application.get_env(:goth, :json)
    Application.put_env(:goth, :json, nil, persistent: true)
    Application.stop(:goth)

    # Fake project response
    project = "test-project"
    Bypass.expect(bypass, fn(conn) ->
      uri = "/computeMetadata/v1/project/project-id"
      assert(conn.request_path == uri, "Goth should ask for project ID")
      Plug.Conn.resp(conn, 200, project)
    end)
    Application.start(:goth)

    assert({:ok, :metadata} == Config.get(:token_source),
      "Token source should be Google Cloud metadata")
    assert({:ok, "test-project"} == Config.get(:project_id),
      "Config should return project from metadata")

    # Restore original config
    Application.put_env(:goth, :json, current_json, persistent: true)
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "config can be overriden manually" do
    project = "different"
    Application.put_env(:goth, :project_id, project, persistent: true)
    Application.stop(:goth)

    Application.start(:goth)
    assert {:ok, ^project} = Config.get(:project_id)

    Application.put_env(:goth, :project_id, nil, persistent: true)
    Application.stop(:goth)
    Application.start(:goth)
  end
end
