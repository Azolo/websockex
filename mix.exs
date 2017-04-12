defmodule WebSockex.Mixfile do
  use Mix.Project

  def project do
    [app: :websockex,
     version: "0.1.0",
     elixir: "~> 1.3",
     description: "An Elixir WebSocket client",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
     package: package(),
     deps: deps()]
  end

  defp elixirc_paths(:test), do: ['lib', 'test/support']
  defp elixirc_paths(_), do: ['lib']

  def application do
    [applications: [:logger, :ssl, :crypto],
     mod: {WebSockex, []}]
  end

  defp deps do
    [{:ex_doc, "~> 0.14", only: :dev},
     {:cowboy, "~> 1.0.0", only: :test},
     {:plug, "~> 1.0", only: :test}]
  end

  defp package do
    %{licenses: ["MIT"],
      maintainers: ["Justin Baker"],
      links: %{"GitHub" => "https://github.com/Azolo/websockex",
               "Docs" => "https://hexdocs.pm/websockex"}}
  end
end
