defmodule GoogleAuth.Token do
  alias GoogleAuth.TokenStore
  alias GoogleAuth.Client

  defstruct [:token, :type, :expires]

  def from_response_json(json) do
    {:ok, attrs} = json |> Poison.decode
    %__MODULE__{
      token:   attrs["access_token"],
      type:    attrs["token_type"],
      expires: :os.system_time(:seconds) + attrs["expires_in"]
    }
  end

  def for_scope(scope) do
    case TokenStore.find(scope) do
      :error       -> retrieve_and_store!(scope)
      {:ok, token} -> {:ok, token}
    end
  end

  defp retrieve_and_store!(scope) do
    {:ok, token} = Client.get_access_token(scope)
    TokenStore.store(scope, token)
    {:ok, token}
  end
end
