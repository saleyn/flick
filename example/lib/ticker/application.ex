defmodule Ticker.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TickerWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Ticker.Supervisor)
  end
end
