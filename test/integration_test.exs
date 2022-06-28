defmodule IntegrationTest do
  use ExUnit.Case
  @moduletag :integration

  setup do
    :ok = Application.stop(:goth)
    env = Application.get_all_env(:goth)
    for {key, _} <- env, do: Application.delete_env(:goth, key)
    :ok = Application.start(:goth)

    on_exit(fn ->
      :ok = Application.stop(:goth)
      :application.set_env(goth: env)
      :ok = Application.start(:goth)
    end)
  end

  test "service account", c do
    System.put_env("GOOGLE_APPLICATION_CREDENTIALS", Path.expand("config/credentials_service_account.json"))
    now = System.system_time(:second)

    start_supervised!({Goth, name: c.test})
    token = Goth.fetch!(c.test)
    assert "ya29." <> _ = token.token
    assert_in_delta token.expires, now + 3599, 1

    assert Goth.Config.get(:token_source) == {:ok, :oauth_jwt}
  after
    System.delete_env("GOOGLE_APPLICATION_CREDENTIALS")
  end

  test "refresh token", c do
    # Goth.Config needs a project id. For service account, it will get it from the credentials
    # file. For refresh token users would set GOOGLE_CLOUD_PROJECT and such. For this test,
    # let's use the project id from our fixture.
    project_id =
      "config/credentials_service_account.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("project_id")

    System.put_env("GOOGLE_CLOUD_PROJECT", project_id)

    System.put_env(
      "GOOGLE_APPLICATION_CREDENTIALS_JSON",
      Path.expand("config/credentials_refresh_token.json") |> File.read!()
    )

    now = System.system_time(:second)

    start_supervised!({Goth, name: c.test})
    token = Goth.fetch!(c.test)
    assert "ya29." <> _ = token.token
    assert_in_delta token.expires, now + 3599, 1

    assert Goth.Config.get(:token_source) == {:ok, :oauth_refresh}
  after
    System.delete_env("GOOGLE_APPLICATION_CREDENTIALS_JSON")
    System.delete_env("GOOGLE_CLOUD_PROJECT")
  end
end
