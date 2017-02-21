defmodule WebSockex.Mixfile do
  use Mix.Project

  def project do
    [app: :websockex,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
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
end
