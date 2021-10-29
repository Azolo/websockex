defmodule WebSockex.Mixfile do
  use Mix.Project
  @env Mix.env()

  def project do
    [
      app: :websockex,
      name: "WebSockex",
      version: "0.4.3",
      elixir: "~> 1.3",
      description: "An Elixir WebSocket client",
      source_url: "https://github.com/Azolo/websockex",
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
    applications = [:logger, :ssl, :crypto] ++ applications(otp_release())
    [
      applications: applications,
      mod: {WebSockex.Application, []},
      extra_applications: extra_application(@env)
    ]
  end

  defp extra_application(env) when env in [:dev, :test], do: [:plug, :cowboy]
  defp extra_application(_env), do: []

  defp applications(otp_release) when otp_release >= 21 do
    [:telemetry]
  end

  defp applications(_), do: []

  defp deps do
    [
      {:ex_doc, "~> 0.14", only: :dev, runtime: false},
      {:plug_cowboy, "~> 1.0.0", only: [:dev, :test]},
      {:ranch, "~> 1.8", only: [:dev, :test]},
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
end
