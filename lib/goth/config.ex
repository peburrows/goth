defmodule Goth.Config do
  @moduledoc """
  `Goth.Config` is a `GenServer` that holds the current configuration.
  This configuration is loaded from one of three places:

  1. a JSON string passed in via your application's config
  2. a ENV variable passed in via your application's config
  3. The Application Default Credentials, as defined by
     https://developers.google.com/identity/protocols/application-default-credentials

  The `Goth.Config` server exists mostly for other parts of your application
  (or other libraries) to pull the current configuration state,
  via `Goth.Config.get/1`. If necessary, you can also set config values via
  `Goth.Config.set/2`
  """

  use GenServer
  alias Goth.Client

  def start_link do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  def init(:ok) do
    config = from_json() ||
             from_config() ||
             from_creds_file() ||
             from_gcloud_adc() ||
             from_metadata()
    project_id = determine_project_id(config)
    actor_email = Application.get_env(:goth, :actor_email)
    config =
      config
      |> Map.put("project_id", project_id)
      |> Map.put("actor_email", actor_email)
    {:ok, config}
  end

  defp from_json() do
    case Application.get_env(:goth, :json) do
      nil -> nil
      {:system, var} -> decode_json(System.get_env(var))
      json -> decode_json(json)
    end
  end

  defp from_config() do
    Application.get_env(:goth, :config)
  end

  defp from_creds_file() do
    case System.get_env("GOOGLE_APPLICATION_CREDENTIALS") do
      nil -> nil
      filename -> filename |> File.read!() |> decode_json()
    end
  end

  # Search the well-known path for application default credentials provided
  # by the gcloud sdk. Note there are different paths for unix and windows.
  defp from_gcloud_adc() do
    config_root_dir = Application.get_env(:goth, :config_root_dir)
    path_root = if config_root_dir == nil do
      case :os.type() do
        {:win32, _} ->
          System.get_env("APPDATA") || ""
        {:unix, _} ->
          home_dir = System.get_env("HOME") || ""
          Path.join([home_dir, ".config"])
      end
    else
      config_root_dir
    end

    path = Path.join([path_root, "gcloud", "application_default_credentials.json"])
    if File.regular?(path) do
      path |> File.read!() |> decode_json()
    else
      nil
    end
  end

  defp from_metadata() do
    %{"token_source" => :metadata}
  end

  defp determine_project_id(config) do
    case Application.get_env(:goth, :project_id) || System.get_env("GOOGLE_CLOUD_PROJECT") ||
           System.get_env("GCLOUD_PROJECT") || System.get_env("DEVSHELL_PROJECT_ID") ||
           config["project_id"] do
      nil ->
        try do
          Client.retrieve_metadata_project()
        rescue
          e in HTTPoison.Error ->
            case e do
              %HTTPoison.Error{reason: :nxdomain} ->
                raise " Failed to retrieve project data from GCE internal metadata service.
                   Either you haven't configured your GCP credentials, you aren't running on GCE, or both.
                   Please see README.md for instructions on configuring your credentials."

              _ ->
                e
            end
        end

      project_id ->
        project_id
    end
  end

  # Decodes JSON (if configured) and sets oauth token source
  defp decode_json(json) do
    json
    |> Poison.decode!
    |> set_token_source
  end

  defp set_token_source(map = %{"private_key" => _}) do
    Map.put(map, "token_source", :oauth_jwt)
  end
  defp set_token_source(map = %{"refresh_token" => _, "client_id" => _, "client_secret" => _}) do
    Map.put(map, "token_source", :oauth_refresh)
  end

  def set(key, value) when is_atom(key), do: key |> to_string |> set(value)
  def set(key, value) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  def get(key) when is_atom(key), do: key |> to_string |> get
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def handle_call({:set, key, value}, _from, keys) do
    {:reply, :ok, Map.put(keys, key, value)}
  end

  def handle_call({:get, key}, _from, keys) do
    {:reply, Map.fetch(keys, key), keys}
  end
end
