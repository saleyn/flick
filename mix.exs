defmodule Flick.MixProject do
  use Mix.Project

  def project do
    [
      app:               :flick,
      version:           "0.1.0",
      elixir:            "~> 1.13",
      start_permanent:   Mix.env() == :prod,
      description:       "Binary (Erlang External Term Format) WebSocket transport for Phoenix, paired with erlb.js",
      elixirc_paths:     elixirc_paths(Mix.env()),
      package:           package(),
      deps:              deps(),
      docs:              docs()
    ]
  end

  defp docs do
    [
      main:   "readme",
      extras: ["README.md", "LICENSE"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      files:       ~w(lib priv .formatter.exs mix.* README* LICENSE*),
      licenses:    ["MIT"],
      maintainers: ["Serge Aleynikov"],
      keywords:    ["elixir", "phoenix", "websocket", "etf", "eetf", "erlang", "term_to_binary"],
      links:       %{
        "GitHub"  => "https://github.com/saleyn/flick",
        "erlb.js" => "https://github.com/saleyn/erlb.js"
      }
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:websock_adapter, "~> 0.6", override: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:bandit, "~> 1.5", only: :test},
      {:phoenix, "~> 1.8", optional: true}
    ]
  end
end
