defmodule GoogleAuth.Mixfile do
  use Mix.Project

  def project do
    [app: :google_auth,
     version: "0.0.1",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      mod: {GoogleAuth, []},
      applications: [:logger, :httpoison]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:json_web_token, "~> 0.2", github: "garyf/json_web_token_ex"},
     {:httpoison, "~> 0.8.0"},
     {:poison, "~> 2.0.0"},
     {:bypass, "~> 0.1", only: :test},
     {:mix_test_watch, "~> 0.2.5", only: :dev}]
  end
end
