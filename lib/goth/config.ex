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
             from_metadata()
    project_id = determine_project_id(config)
    {:ok, Map.put(config, "project_id", project_id)}
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

  defp from_metadata() do
    %{"token_source" => :metadata}
  end

  defp determine_project_id(config) do
    Application.get_env(:goth, :project_id) ||
      System.get_env("GOOGLE_CLOUD_PROJECT") ||
      System.get_env("GCLOUD_PROJECT") ||
      System.get_env("DEVSHELL_PROJECT_ID") ||
      config["project_id"] ||
      Client.retrieve_metadata_project()
  end

  # Decodes JSON (if configured) and sets oauth token source
  defp decode_json(json) do
    json
    |> Poison.decode!
    |> Map.put("token_source", :oauth)
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
