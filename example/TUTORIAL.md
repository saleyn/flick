# Migrating a Phoenix App from JSON Polling to ETF WebSocket with Flick

This tutorial walks through a concrete, minimal Phoenix application — a live
stock-price ticker — and shows every change needed to replace HTTP JSON polling
with a persistent binary WebSocket using `:flick`.

## The starting point

The `example/` directory contains the app **before** flick. It has:

- `Ticker.PriceFeed` — a GenServer that publishes a candle map for each symbol
  every second via `Phoenix.PubSub`.
- `TickerWeb.CandleController` — a plain JSON API endpoint at `GET /api/candles`
  that returns the latest candles.
- `assets/js/app.js` — calls `fetch("/api/candles")` every second with
  `setInterval`, parses the JSON response, and updates the DOM.

### What's wrong with polling

| Problem | Detail |
|---------|--------|
| Overhead per tick | HTTP handshake + JSON serialization + JSON parsing on every update |
| Latency | Client always lags by up to one full interval |
| Server load | N clients × 1 req/s, each paying full HTTP overhead |
| Wasted work | All candles are returned even if only one symbol changed |

---

## The goal

Replace the poll loop with a single persistent WebSocket per client. The server
pushes candles as they arrive via PubSub. The payload is Erlang External Term
Format (ETF) — binary, compact, and zero-copy on the server side.

The `after/` subdirectory contains the finished state of each changed file.

---

## Step 1 — Add the dependency

In `mix.exs`, add `:flick` and ensure `:websock_adapter` is explicit:

```elixir
# mix.exs
defp deps do
  [
    {:phoenix,         "~> 1.7"},
    {:bandit,          "~> 1.5"},
    {:websock_adapter, "~> 0.5"},   # must be explicit for mix flick.install
    {:jason,           "~> 1.4"},
    {:flick,           "~> 0.1"}    # add this
  ]
end
```

```bash
mix deps.get
```

---

## Step 2 — Run the installer

```bash
mix flick.install
```

The installer prints a plan and asks for confirmation. It performs every
remaining step automatically:

```
App:        ticker  (TickerWeb)
WebSock:    TickerWeb.MySocket
Controller: TickerWeb.MySocketController
WS path:    /ws

Planned actions:
  write   assets/vendor/flick.min.js.gz
  write   priv/static/assets/js/flick.min.js.gz
  patch   lib/ticker_web/components/layouts/root.html.heex  (add <script> tag)
  create  lib/ticker_web/my_socket.ex
  create  lib/ticker_web/my_socket_controller.ex
  patch   lib/ticker_web/router.ex  (insert get route)
  append  assets/js/app.js  (flick WebSocket hook)

Proceed? [y/N]
```

Press `y`. All files are written.

---

## Step 3 — Fill in the WebSock module

The installer creates `lib/ticker_web/my_socket.ex` as a skeleton. Open it and
add the PubSub subscription and the push logic:

**Before (generated skeleton):**

```elixir
defmodule TickerWeb.MySocket do
  @behaviour WebSock

  @impl WebSock
  def init(args) do
    {:ok, %{args: args}}
  end

  @impl WebSock
  def handle_in(_frame, state), do: {:ok, state}

  @impl WebSock
  def handle_info(_msg, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, _state), do: :ok
end
```

**After (your business logic):**

```elixir
defmodule TickerWeb.MySocket do
  @behaviour WebSock

  @impl WebSock
  def init(params) do
    symbol = Map.get(params, "symbol", "AAPL")
    Ticker.PriceFeed.subscribe(symbol)      # subscribe to PubSub
    {:ok, %{symbol: symbol}}
  end

  @impl WebSock
  def handle_in(_frame, state), do: {:ok, state}   # read-only feed

  @impl WebSock
  def handle_info({:candle, candle}, state) do
    {:push, {:binary, :erlang.term_to_binary(candle)}, state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, _state), do: :ok
end
```

Two changes from the skeleton:
1. `init/1` reads a `"symbol"` query param and subscribes to the PubSub topic.
2. A `handle_info/2` clause encodes the candle map with
   `:erlang.term_to_binary/1` and pushes it as a binary frame.

See [after/lib/ticker_web/my_socket.ex](after/lib/ticker_web/my_socket.ex).

---

## Step 4 — Update the JS hook in app.js

The installer appended a starter hook to `assets/js/app.js`:

```javascript
// flick WebSocket — /ws
const _flickProto = location.protocol === "https:" ? "wss" : "ws"
const _flickUrl   = `${_flickProto}://${location.host}/ws`
const _flickWs    = new WebSocket(_flickUrl)
_flickWs.binaryType = "arraybuffer"
_flickWs.onmessage = (event) => {
  const msg  = window.Flick.decode(event.data)
  const type = msg.type && msg.type.value ? msg.type.value : String(msg.type)
  console.log("flick message:", type, msg)
}
```

Replace the `console.log` with your actual dispatch logic, and remove the old
`setInterval` poll:

```javascript
// REMOVE the old polling code:
// async function poll() { ... }
// setInterval(poll, 1000)

// UPDATE the flick hook — append ?symbol=AAPL to the URL, call updateRow:
const _flickProto = location.protocol === "https:" ? "wss" : "ws"
const _flickUrl   = `${_flickProto}://${location.host}/ws?symbol=AAPL`
const _flickWs    = new WebSocket(_flickUrl)
_flickWs.binaryType = "arraybuffer"
_flickWs.onmessage = (event) => {
  const candle = window.Flick.decode(event.data)
  updateRow(candle)
}
```

One thing to note: the `symbol` field in a candle map is an Elixir atom
(`:AAPL`). `flick.js` decodes atoms as `ErlAtom` objects, so access the string
value via `.value`:

```javascript
// BEFORE (JSON polling — symbol was a plain string):
const id = "row-" + candle.symbol

// AFTER (ETF WebSocket — symbol is an ErlAtom):
const id = "row-" + candle.symbol.value
```

See [after/assets/js/app.js](after/assets/js/app.js) for the complete file.

---

## Step 5 — Remove the old JSON endpoint

The polling API is no longer needed. Delete (or keep for other clients):

- `lib/ticker_web/controllers/candle_controller.ex`
- The `get "/api/candles"` route in `router.ex`
- The `poll()` function and `setInterval` in `app.js`

---

## Step 6 — Restart and verify

```bash
mix assets.deploy   # or just restart the dev server
```

Open the page. In the browser DevTools → Network → WS, you should see:

- A single WebSocket connection to `/ws?symbol=AAPL`.
- Binary frames arriving roughly once per second.
- The table updating in real time without any HTTP polling traffic.

---

## What changed — summary

| | Before | After |
|-|--------|-------|
| Transport | HTTP poll every 1 s | Persistent WebSocket |
| Encoding | JSON (text) | ETF (binary) |
| Server push | No — client must ask | Yes — server pushes on PubSub event |
| Per-update overhead | Full HTTP round-trip + JSON encode + JSON parse | Single binary frame + `:erlang.term_to_binary/1` |
| Client decoder | `JSON.parse()` (built-in) | `window.Flick.decode()` (pre-built, 5 KB gzipped) |
| Atom fields | Strings | `ErlAtom{value: "..."}` — access via `.value` |
| New files | — | `my_socket.ex`, `my_socket_controller.ex` |
| Changed files | `mix.exs`, `router.ex`, `app.js`, layout | same |

---

## Going further

- **Multiple symbols per connection** — pass a comma-separated `symbols` param
  and subscribe to multiple PubSub topics in `init/1`.
- **Client-to-server messages** — handle `handle_in/2` to let the client
  resubscribe without reconnecting.
- **Phoenix Channels** — if you need topics, join/leave, and broadcast to
  multiple subscribers, see the
  [Phoenix Channels over ETF](../README.md#phoenix-channels-over-etf) section
  and run `mix flick.install --channels --no-boilerplate`.
