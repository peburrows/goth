defmodule Goth.Config do
  @moduledoc """
  `Goth.Config` is a `GenServer` that holds the current configuration.
  This configuration is loaded from one of four places:

  1. a JSON string passed in via your application's config
  2. a ENV variable passed in via your application's config
  3. The Application Default Credentials, as defined by
     https://developers.google.com/identity/protocols/application-default-credentials
  4. an `init/1` callback on a custom config module. This init function is
     passed the current config and must return an `{:ok, config}` tuple

  The `Goth.Config` server exists mostly for other parts of your application
  (or other libraries) to pull the current configuration state,
  via `Goth.Config.get/1`. If necessary, you can also set config values via
  `Goth.Config.set/2`
  """

  use GenServer
  alias Goth.Client

  # this using macro isn't actually necessary,
  defmacro __using__(_opts) do
    quote do
      @behaviour Goth.Config
    end
  end

  @optional_callbacks init: 1

  @doc """
  A callback executed when the Goth.Config server starts.

  The sole argument is the `:goth` configuration as stored in the
  application environment. It must return `{:ok, keyword}` with the updated
  list of configuration.

  To have your module's `init/1` callback called at startup, add your module
  as the `:config_module` in the application environment:

      config :goth, config_module: MyConfig
  """
  @callback init(config :: Keyword.t()) :: {:ok, Keyword.t()}

  def start_link(envs) do
    GenServer.start_link(__MODULE__, envs, name: __MODULE__)
  end

  def init(envs) do
    {:ok, dynamic_config} =
      envs
      |> config_mod_init()

    dynamic_config
    |> Keyword.pop(:disabled, false)
    |> load_and_init()
  end

  # We have been configured as `disabled` so just start with an empty configuration
  defp load_and_init({true, _config}) do
    {:ok, %{}}
  end

  defp load_and_init({false, app_config}) do
    config =
      from_json(app_config) || from_config(app_config) || from_creds_file(app_config) ||
        from_gcloud_adc(app_config) || from_metadata(app_config)
    config =
      config
      |> map_config()
      |> Enum.map(fn {account, config} ->
        actor_email = Keyword.get(app_config, :actor_email)
        project_id = determine_project_id(config, app_config)

        {
          account,
          config
          |> Map.put("project_id", project_id)
          |> Map.put("actor_email", actor_email)
        }
      end)
      |> Enum.into(%{})

    {:ok, config}
  end

  def map_config(config) when is_map(config), do: %{default: config}

  def map_config(config) when is_list(config) do
    config
    |> Enum.map(fn config ->
      {
        config["client_email"],
        config
      }
    end)
    |> Enum.into(%{})
  end

  def add_config(config) when is_map(config) do
    config = set_token_source(config)
    GenServer.call(__MODULE__, {:add_config, config["client_email"], config})
  end

  defp config_mod_init(config) do
    case Keyword.get(config, :config_module) do
      nil ->
        {:ok, config}

      mod ->
        if Code.ensure_loaded?(mod) and function_exported?(mod, :init, 1) do
          mod.init(config)
        else
          {:ok, config}
        end
    end
  end

  defp from_json(config) do
    case Keyword.get(config, :json) do
      nil -> nil
      {:system, var} -> decode_json(System.get_env(var))
      json -> decode_json(json)
    end
  end

  defp from_config(config) do
    Keyword.get(config, :config)
  end

  defp fetch_creds_filename do
    default_path = Path.expand("~/.config/gcloud/application_default_credentials.json")
    case {System.fetch_env("GOOGLE_APPLICATION_CREDENTIALS"), File.regular?(default_path)} do
      {{:ok, filename}, _} -> {:ok, filename}
      {_, true} -> {:ok, default_path}
    end
  end

  defp from_creds_file(_config) do
    case fetch_creds_filename do
      {:ok, filename} -> filename |> File.read!() |> decode_json()
      {:error, _} -> nil
    end
  end

  # Search the well-known path for application default credentials provided
  # by the gcloud sdk. Note there are different paths for unix and windows.
  defp from_gcloud_adc(config) do
    # config_root_dir = Application.get_env(:goth, :config_root_dir)
    config_root_dir = Keyword.get(config, :config_root_dir)

    path_root =
      if config_root_dir == nil do
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

  defp from_metadata(_config) do
    %{"token_source" => :metadata}
  end

  defp determine_project_id(config, dynamic_config) do
    case Keyword.get(dynamic_config, :project_id) || System.get_env("GOOGLE_CLOUD_PROJECT") ||
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
    |> Jason.decode!()
    |> set_token_source
  end

  defp set_token_source(map = %{"private_key" => _}) do
    Map.put(map, "token_source", :oauth_jwt)
  end

  defp set_token_source(map = %{"refresh_token" => _, "client_id" => _, "client_secret" => _}) do
    Map.put(map, "token_source", :oauth_refresh)
  end

  defp set_token_source(list) when is_list(list) do
    Enum.map(list, fn config ->
      set_token_source(config)
    end)
  end

  @doc """
  Set a value in the config.
  """
  @spec set(String.t() | atom, any()) :: :ok
  def set(key, value) when is_atom(key), do: key |> to_string |> set(value)

  def set(key, value), do: set(:default, key, value)

  def set(account, key, value) do
    GenServer.call(__MODULE__, {:set, account, key, value})
  end

  @doc """
  Retrieve a value from the config.
  """
  @spec get(String.t() | atom()) :: {:ok, any()} | :error
  def get(key) when is_atom(key), do: key |> to_string() |> get()
  def get(key), do: get(:default, key)

  @spec get(String.t() | atom(), String.t() | atom()) :: {:ok, any()} | :error
  def get(account, key) when is_atom(key) do
    get(account, key |> to_string())
  end

  def get(account, key) do
    GenServer.call(__MODULE__, {:get, account, key})
  end

  def handle_call({:set, account, key, value}, _from, keys) do
    {:reply, :ok, put_in(keys, [account, key], value)}
  end

  def handle_call({:add_config, account, config}, _from, keys) do
    {:reply, :ok, Map.put(keys, account, config)}
  end

  def handle_call({:get, account, key}, _from, keys) do
    case Map.fetch(keys, account) do
      {:ok, config} -> {:reply, Map.fetch(config, key), keys}
      :error -> {:reply, :error, keys}
    end
  end
end
