defmodule Goth.Mixfile do
  use Mix.Project

  @version "1.3.0-rc.0"
  @source_url "https://github.com/peburrows/goth"

  def project do
    [
      app: :goth,
      version: @version,
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.10",
      source_url: @source_url,
      name: "Goth",
      description: description(),
      docs: [source_ref: "v#{@version}", main: "readme", extras: ["README.md"]],
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Goth.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jose, "~> 1.10"},
      {:jason, "~> 1.1"},
      {:hackney, "~> 1.0", optional: true},
      {:bypass, "~> 2.1", only: :test},
      {:mix_test_watch, "~> 0.2", only: :dev},
      {:ex_doc, "~> 0.19", only: :dev},
      {:credo, "~> 0.8", only: [:test, :dev]},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
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
      links: %{"GitHub" => @source_url}
    ]
  end
end
