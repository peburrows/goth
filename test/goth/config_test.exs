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
    state = "test/data/test-credentials.json" |> Path.expand |> File.read! |> Poison.decode!
    state |> Map.keys |> Enum.each(fn(key) ->
      assert {:ok, state[key]} == Config.get(key)
    end)
  end

  test "the initial state has the token_source set to oauth_jwt" do
    assert {:ok, :oauth_jwt} == Config.get(:token_source)
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

  test "GOOGLE_APPLICATION_CREDENTIALS is read" do
    # The test configuration sets an example JSON blob. We override it briefly
    # during this test.
    current_json = Application.get_env(:goth, :json)
    Application.put_env(:goth, :json, nil, persistent: true)
    System.put_env("GOOGLE_APPLICATION_CREDENTIALS",
                   "test/data/test-credentials-2.json")
    Application.stop(:goth)

    Application.start(:goth)
    state = "test/data/test-credentials-2.json" |> Path.expand |> File.read! |> Poison.decode!
    state |> Map.keys |> Enum.each(fn(key) ->
      assert {:ok, state[key]} == Config.get(key)
    end)
    assert {:ok, :oauth_jwt} == Config.get(:token_source)

    # Restore original config
    Application.put_env(:goth, :json, current_json, persistent: true)
    System.delete_env("GOOGLE_APPLICATION_CREDENTIALS")
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "gcloud default credentials are found", %{bypass: bypass} do
    # The test configuration sets an example JSON blob. We override it briefly
    # during this test.
    current_json = Application.get_env(:goth, :json)
    current_home = Application.get_env(:goth, :config_root_dir)
    Application.put_env(:goth, :json, nil, persistent: true)
    Application.put_env(:goth, :config_root_dir, "test/data/home", persistent: true)
    Application.stop(:goth)

    # Fake project response because the ADC doesn't embed a project.
    project = "test-project"
    Bypass.expect(bypass, fn(conn) ->
      uri = "/computeMetadata/v1/project/project-id"
      assert(conn.request_path == uri, "Goth should ask for project ID")
      Plug.Conn.resp(conn, 200, project)
    end)

    Application.start(:goth)
    state = "test/data/home/gcloud/application_default_credentials.json" |> Path.expand |> File.read! |> Poison.decode!
    state |> Map.keys |> Enum.each(fn(key) ->
      assert {:ok, state[key]} == Config.get(key)
    end)
    assert {:ok, :oauth_refresh} == Config.get(:token_source)

    # Restore original config
    Application.put_env(:goth, :json, current_json, persistent: true)
    Application.put_env(:goth, :config_root_dir, current_home, persistent: true)
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "project_id can be overridden in config" do
    project = "different"
    Application.put_env(:goth, :project_id, project, persistent: true)
    Application.stop(:goth)

    Application.start(:goth)
    assert {:ok, project} == Config.get(:project_id)

    Application.put_env(:goth, :project_id, nil, persistent: true)
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "project_id can be overridden by environment variables" do
    project_from_env = "different1"
    project_from_devshell = "different2"
    System.put_env("DEVSHELL_PROJECT_ID", project_from_devshell)
    Application.stop(:goth)

    Application.start(:goth)
    assert {:ok, project_from_devshell} == Config.get(:project_id)

    System.put_env("GOOGLE_CLOUD_PROJECT", project_from_env)
    Application.stop(:goth)

    Application.start(:goth)
    assert {:ok, project_from_env} == Config.get(:project_id)

    System.delete_env("DEVSHELL_PROJECT_ID")
    System.delete_env("GOOGLE_CLOUD_PROJECT")
    Application.stop(:goth)
    Application.start(:goth)
  end

  test "the config_module is allowed to override config" do
    Application.put_env(:goth, :config_module, Goth.TestConfigMod)
    Application.stop(:goth)

    Application.start(:goth)
    assert {:ok, :val} == Goth.Config.get(:actor_email)

    Application.delete_env(:goth, :config_module)
    Application.stop(:goth)
    Application.start(:goth)
  end
end
