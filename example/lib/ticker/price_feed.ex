defmodule Ticker.PriceFeed do
  @moduledoc """
  Simulated price feed. Broadcasts a new candle every second via Phoenix.PubSub.

  Each candle is a map with keys: symbol, open, high, low, close, volume, time.
  Subscribers receive {:candle, candle_map} messages.
  """
  use GenServer

  @symbols ~w(AAPL MSFT GOOG)
  @interval_ms 1_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def subscribe(symbol),
    do: Phoenix.PubSub.subscribe(Ticker.PubSub, "candles:#{symbol}")

  @impl GenServer
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    for symbol <- @symbols do
      candle = %{
        symbol: symbol,
        open:   rand_price(),
        high:   rand_price(),
        low:    rand_price(),
        close:  rand_price(),
        volume: :rand.uniform(10_000),
        time:   System.system_time(:second)
      }

      Phoenix.PubSub.broadcast(Ticker.PubSub, "candles:#{symbol}", {:candle, candle})
    end

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, @interval_ms)
  defp rand_price, do: Float.round(100 + :rand.uniform() * 50, 2)
end
