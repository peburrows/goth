defmodule IntegrationTest do
  use ExUnit.Case
  @moduletag :integration

  describe "from source option" do
    test "gets the service account token", %{test: test} do
      credentials =
        Path.expand("config/credentials.json")
        |> File.read!()
        |> Jason.decode!()

      Application.stop(:goth)
      Application.start(:goth)

      assert {:ok, _} = Goth.start_link(name: test, source: {:service_account, credentials})
      assert {:ok, %Goth.Token{}} = Goth.fetch(test)
    end

    test "gets the refresh token", %{test: test} do
      credentials =
        Path.expand("config/gcloud/application_default_credentials.json")
        |> File.read!()
        |> Jason.decode!()

      Application.stop(:goth)
      Application.start(:goth)

      assert {:ok, _} = Goth.start_link(name: test, source: {:refresh_token, credentials})
      assert {:ok, %Goth.Token{}} = Goth.fetch(test)
    end
  end

  # Sometimes one of the tests fails, probably coz it somehow conflicts with another test
  describe "from system env" do
    setup tags do
      current_json = Application.get_env(:goth, :json)
      root_dir = Application.get_env(:goth, :config_root_dir)

      if path = tags[:path] do
        Application.put_env(:goth, :config_root_dir, path, persistent: true)
      end

      Application.put_env(:goth, :json, nil, persistent: true)

      on_exit(fn ->
        Application.put_env(:goth, :json, current_json, persistent: true)
        Application.put_env(:goth, :config_root_dir, root_dir, persistent: true)
      end)

      :ok
    end

    test "gets the service account token from GOOGLE_APPLICATION_CREDENTIALS", %{test: test} do
      System.put_env("GOOGLE_APPLICATION_CREDENTIALS", Path.expand("config/credentials.json"))

      assert {:ok, _} = Goth.start_link(name: test)
      assert {:ok, %Goth.Token{}} = Goth.fetch(test)
      assert {:ok, :oauth_jwt} = Goth.Config.get(:token_source)

      System.delete_env("GOOGLE_APPLICATION_CREDENTIALS")
    end

    @tag path: Path.expand("config")
    test "gets the refresh token from GOOGLE_CLOUD_PROJECT", %{test: test} do
      System.put_env("GOOGLE_CLOUD_PROJECT", System.fetch_env!("PROJECT_ID"))

      assert {:ok, _} = Goth.start_link(name: test)
      assert {:ok, %Goth.Token{}} = Goth.fetch(test)
      assert {:ok, :oauth_refresh} = Goth.Config.get(:token_source)

      System.delete_env("GOOGLE_CLOUD_PROJECT")
    end
  end
end
