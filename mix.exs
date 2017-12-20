defmodule Goth.Mixfile do
  use Mix.Project

  def project do
    [app: :goth,
     version: "0.7.2",
     description: description(),
     package: package(),
     elixir: "~> 1.4",
     deps: deps()]
  end

  def application do
    [
      mod: {Goth, []},
      applications: [:json_web_token, :logger, :httpoison]
    ]
  end

  defp deps do
    [{:json_web_token, "~> 0.2.10"},
     {:httpoison, "~> 0.11"},
     {:poison, "~> 2.1 or ~> 3.0"},
     {:bypass, "~> 0.1",         only: :test},
     {:mix_test_watch, "~> 0.2", only: :dev},
     {:ex_doc, "~> 0.11.3",      only: :dev},
     {:earmark, "~> 0.2",        only: :dev},
     {:credo, "~> 0.8",          only: [:test, :dev]}
    ]
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
