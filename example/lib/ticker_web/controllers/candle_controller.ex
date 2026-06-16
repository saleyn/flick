defmodule TickerWeb.CandleController do
  use TickerWeb, :controller

  # BEFORE flick: returns the latest candle for each symbol as JSON.
  # Called by the client every second via setInterval poll.
  def index(conn, _params) do
    candles = Ticker.PriceFeed.latest_candles()
    json(conn, candles)
  end
end
