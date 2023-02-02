defmodule WebSockex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :websockex,
      name: "WebSockex",
      version: "0.4.3",
      elixir: "~> 1.7",
      description: "An Elixir WebSocket client",
      source_url: "https://github.com/Azolo/websockex",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      dialyzer: dialyzer(),
      deps: deps(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ['lib', 'test/support']
  defp elixirc_paths(_), do: ['lib']

  def application do
    applications = [:logger, :ssl, :crypto] ++ applications(otp_release())
    [extra_applications: applications, mod: {WebSockex.Application, []}]
  end

  defp applications(otp_release) when otp_release >= 21 do
    [:telemetry]
  end

  defp applications(_), do: []

  defp deps do
    [
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:cowboy, "~> 2.9", only: :test},
      {:plug_cowboy, "~> 2.5", only: :test},
      {:dialyxir, "~> 1.0", only: [:test, :dev], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.12", only: :test}
    ] ++ optional_deps(otp_release())
  end

  defp optional_deps(otp_release) when otp_release >= 21 do
    [{:telemetry, "~> 1.0"}]
  end

  defp optional_deps(_), do: []

  defp package do
    %{
      licenses: ["MIT"],
      maintainers: ["Justin Baker"],
      links: %{"GitHub" => "https://github.com/Azolo/websockex"}
    }
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme"
    ]
  end

  defp otp_release do
    :erlang.system_info(:otp_release) |> to_string() |> String.to_integer()
  end

  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_add_apps: [:mix, :eex],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/websockex.plt"}
    ]
  end
end
