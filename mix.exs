defmodule WebSockex.Mixfile do
  use Mix.Project

  @source_url "https://github.com/Azolo/websockex"
  @version "0.4.2"

  def project do
    [
      app: :websockex,
      name: "WebSockex",
      version: @version,
      elixir: "~> 1.3",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ['lib', 'test/support']
  defp elixirc_paths(_), do: ['lib']

  def application do
    [
      applications: [:logger, :ssl, :crypto],
      mod: {WebSockex.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:cowboy, "~> 1.0.0", only: :test},
      {:plug, "~> 1.0", only: :test}
    ]
  end

  defp package do
    [
      description: "An Elixir WebSocket client",
      licenses: ["MIT"],
      maintainers: ["Justin Baker"],
      links: %{
        "Changelog" => "https://hexdocs.pm/websockex/changelog.html",
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      main: "readme",
      source_url: @source_url,
      source_ref: "#{@version}"
    ]
  end
end
