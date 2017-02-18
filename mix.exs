defmodule WebSockex.Mixfile do
  use Mix.Project

  def project do
    [app: :websockex,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:logger, :ssl, :crypto],
     mod: {WebSockex, []}]
  end

  defp deps do
    []
  end
end
