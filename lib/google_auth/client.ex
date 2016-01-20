defmodule GoogleAuth.Client do

  def get_access_token(scope) do
    # 1. check the token store
    # 2. get a new token from google
    endpoint = Application.get_env(:google_auth, :endpoint, "https://www.googleapis.com")

    {:ok, response} = HTTPoison.post(Path.join([endpoint, "/oauth2/v4/token"]), jwt(scope), [
      {"Content-Type", "application/x-www-form-urlencoded"}
    ])
    response.body |> Poison.decode
  end

  defp jwt(scope) do
    "generate JWT token here"
  end
end
