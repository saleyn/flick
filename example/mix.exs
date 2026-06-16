defmodule Ticker.MixProject do
  use Mix.Project

  def project do
    [
      app:             :ticker,
      version:         "0.1.0",
      elixir:          "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps:            deps()
    ]
  end

  def application do
    [
      mod:              {Ticker.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:phoenix,          "~> 1.7"},
      {:phoenix_html,     "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:bandit,           "~> 1.5"},
      {:websock_adapter,  "~> 0.5"},
      {:jason,            "~> 1.4"},
      {:flick,      path: ".."}
    ]
  end
end
