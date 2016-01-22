defmodule Goth.Mixfile do
  use Mix.Project

  def project do
    [app: :goth,
     version: "0.0.3",
     description: description,
     package: package,
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
      mod: {Goth, []},
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
    [{:json_web_token, "~> 0.2.4"},
     {:httpoison, "~> 0.8.0"},
     {:poison, "~> 1.5.2"},
     {:bypass, "~> 0.1", only: :test},
     {:mix_test_watch, "~> 0.2.5", only: :dev},
     {:ex_doc, "~> 0.11.3", only: [:dev]},
     {:earmark, "~> 0.2", only: [:dev]}]
  end

  defp description do
    """
    A simple library to generate and retrieve Oauth2 tokens for use with Google Cloud Service accounts.
    """
  end

  defp package do
    [
      maintainers: ["Phil Burrows"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/peburrows/goth"}
    ]
  end
end
