defmodule TickerWeb.MySocket do
  @moduledoc """
  Raw WebSocket handler that streams live candle data as ETF binary frames.

  Generated skeleton by `mix flick.install`, then filled in with business logic:
  - subscribes to the PriceFeed PubSub topic for AAPL on connect
  - pushes each candle as an ETF binary frame when it arrives
  - handles incoming frames as no-ops (read-only feed)
  """
  @behaviour WebSock

  @impl WebSock
  def init(params) do
    symbol = Map.get(params, "symbol", "AAPL")
    Ticker.PriceFeed.subscribe(symbol)
    {:ok, %{symbol: symbol}}
  end

  @impl WebSock
  def handle_in(_frame, state), do: {:ok, state}

  @impl WebSock
  def handle_info({:candle, candle}, state) do
    {:push, {:binary, :erlang.term_to_binary(candle)}, state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, _state), do: :ok
end
