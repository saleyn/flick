![Flick](assets/flick-logo.png){ width=100% }

[![build](https://github.com/saleyn/flick/actions/workflows/ci.yml/badge.svg)](https://github.com/saleyn/flick/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/flick.svg)](https://hex.pm/packages/flick)
[![Hex.pm](https://img.shields.io/hexpm/dt/flick.svg)](https://hex.pm/packages/flick)

Binary (Erlang External Term Format) WebSocket transport for Phoenix,
decoded on the client with [flick.js](priv/flick.js) (vendored from
[erlb.js](https://github.com/saleyn/erlb.js)).

## Features

- **Raw WebSocket + ETF** — push `{:binary, etf_bytes}` frames directly via
  the `WebSock` behaviour; no JSON serialization, no Channels overhead.
- **Phoenix Channels support** — `Flick.Socket.Serializer` and
  `flick_channel_serializer.js` swap out Phoenix's default JSON channel
  serializer with an ETF one, keeping full Channels semantics (topics, join,
  push, broadcast).
- **Zero-dependency client** — `flick.js` is a single self-contained script
  exposing `window.Flick`; no npm package or bundler step required.
- **`mix flick.install`** — one command vendors `flick.js` into your Phoenix
  app, patches the root layout, and optionally minifies via esbuild.
- **`nil` / `true` / `false` round-trip** — Elixir `nil`, `true`, and `false`
  atoms decode to their JS equivalents without any custom mapping.
- **Bidirectional encoding** — `flick.js` can both encode JS objects to ETF
  and decode ETF binary frames back to JS values.

## Why ETF instead of JSON

- **Compact binary encoding** — no string serialization/parsing overhead.
- **Native Elixir types** — `:erlang.term_to_binary/1` on any map/list/number
  with zero custom serialization code.
- **Single shared format** — the same payload structure flows from
  `Phoenix.PubSub` messages straight to the wire.

## Architecture

This uses a **raw WebSocket** via the `WebSock` behaviour and
`WebSockAdapter`, not Phoenix Channels. Channels add their own JSON-based
framing protocol (join/leave/reply envelopes) that would conflict with raw
ETF binary frames. The pieces:

1. A Phoenix controller action that upgrades the connection with
   `WebSockAdapter.upgrade/4`.
2. A `WebSock` behaviour module that pushes `{:binary, etf_bytes}` frames.
3. A router `get` route pointing at the controller action.
4. `flick.js` loaded as a global `<script>` tag, exposing `window.Flick`.
5. Client JS that sets `ws.binaryType = "arraybuffer"` and calls
   `window.Flick.decode(event.data)` on each message.

## Guidelines / Gotchas

### 1. Encode with `:erlang.term_to_binary/1`

Any map, list, atom, number, or binary can be encoded directly:

```elixir
payload = :erlang.term_to_binary(%{
  type:    :tick,
  time:    candle.time,
  open:    candle.open,
  high:    candle.high,
  low:     candle.low,
  close:   candle.close,
  volume:  candle.volume
})

{:push, {:binary, payload}, state}
```

### 2. Atoms decode to `ErlAtom` objects, not strings

`flick.js` decodes Erlang atoms (e.g. `:snapshot`, `:tick`) as `ErlAtom{value:
"snapshot"}` objects, **not** plain JS strings. Always compare via `.value`:

```javascript
const msg  = window.Flick.decode(event.data)
const type = msg.type && msg.type.value ? msg.type.value : String(msg.type)

if (type === "tick") { /* ... */ }
```

### 3. Elixir `nil` decodes to JS `null`

`flick.js`'s `decode_atom` maps the Erlang/Elixir atom `nil` directly to JS
`null` (alongside its existing `true`/`false`/`undefined`/`null` atom
mappings), and `encode_object` maps JS `null` back to the atom `nil` when
encoding. This means `nil` values can be sent and checked with normal JS
falsy checks:

```elixir
payload = :erlang.term_to_binary(%{
  type:    :snapshot,
  candles: history,
  forming: forming   # nil or a candle map — no workaround needed
})
```

```javascript
const f = msg.forming
if (f && typeof f.time === 'number') {
  // real forming candle; f is null when there is none
}
```

### 4. Client setup: binary frames + global decoder

```javascript
const ws = new WebSocket(url)
ws.binaryType = "arraybuffer"

ws.onmessage = (event) => {
  const msg = window.Flick.decode(event.data)
  // ... dispatch on msg.type.value
}
```

`flick.js` is loaded as a plain `<script>` tag (before `app.js`), so
`window.Flick` is available globally to any hook without an import.

---

## Step-by-Step: Adding an ETF WebSocket to a New Project

### 1. Confirm `websock_adapter` is available

Phoenix >= 1.7 depends on `websock_adapter` transitively (via `phoenix` and
`bandit`), so no extra `mix.exs` dependency is usually needed. Verify with:

```bash
mix deps | grep -i websock
```

### 2. Install flick.js with `mix flick.install`

```bash
mix flick.install
```

This copies `flick.js` bundled with the `:flick` dependency, vendors it
under `assets/vendor/flick.js` (source of truth) and
`priv/static/assets/js/flick.js` (served as a static file — loaded via a
`<script>` tag, not bundled by esbuild), and patches
`lib/<app>_web/components/layouts/root.html.heex` to add the `<script>` tag
**before** `app.js`:

```heex
<script src={~p"/assets/js/flick.js"}></script>
<script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
</script>
```

Run `mix help flick.install` for all options:

- `--layout <path>` — point at a non-default root layout file.
- `--skip-layout` — vendor the file(s) without modifying any layout.
- `--channels` — also vendor `flick_channel_serializer.js` to `assets/vendor/`
  (needed for the Phoenix Channels ETF integration below).
- `--minify` — minify the installed JS files in-place using the host app's
  esbuild binary (requires `{:esbuild, "~> 0.8"}` and `mix esbuild.install`).

If you'd rather wire it up manually, copy `flick.js` from the `:flick`
dependency's `priv/flick.js` into `assets/vendor/flick.js` and
`priv/static/assets/js/flick.js`, then add the `<script>` tag to the root
layout as shown above.

### 3. Define the `WebSock` module

```elixir
defmodule MyAppWeb.MySocket do
  @moduledoc """
  Raw WebSocket handler streaming ETF binary frames, decoded client-side
  with flick.js.
  """
  @behaviour WebSock

  @impl WebSock
  def init(args) do
    # subscribe to PubSub, schedule initial push, etc.
    send(self(), :send_snapshot)
    {:ok, %{args: args}}
  end

  @impl WebSock
  def handle_in(_frame, state), do: {:ok, state}

  @impl WebSock
  def handle_info(:send_snapshot, state) do
    payload = :erlang.term_to_binary(%{type: :snapshot, data: []})
    {:push, {:binary, payload}, state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, _state), do: :ok
end
```

### 4. Add a controller action that upgrades the connection

```elixir
defmodule MyAppWeb.MySocketController do
  use MyAppWeb, :controller

  def connect(conn, params) do
    WebSockAdapter.upgrade(conn, MyAppWeb.MySocket, params, [])
  end
end
```

### 5. Add the router route

```elixir
get "/my-ws", MySocketController, :connect
```

### 6. Connect from a JS hook

```javascript
const proto = location.protocol === "https:" ? "wss" : "ws"
const url   = `${proto}://${location.host}/my-ws`
const ws    = new WebSocket(url)
ws.binaryType = "arraybuffer"

ws.onmessage = (event) => {
  const msg  = window.Flick.decode(event.data)
  const type = msg.type && msg.type.value ? msg.type.value : String(msg.type)

  switch (type) {
    case "snapshot":
      // handle msg.data
      break
    default:
      console.warn("Unknown message type:", type)
  }
}
```

### 7. Test

Open the page, check the browser console for the WebSocket connecting and
for decoded messages logging as plain JS objects (maps), with atom fields
appearing as `ErlAtom{value: "..."}`.

## Phoenix Channels over ETF

If you'd rather use Phoenix Channels (join/leave, topics, PubSub broadcasts)
instead of a raw `WebSock` socket, `Flick.Socket.Serializer` and
[flick_channel_serializer.js](priv/flick_channel_serializer.js) replace
Phoenix's default JSON channel serializer with one that encodes the whole
Channels envelope (`join_ref`, `ref`, `topic`, `event`, `payload`) as a
single ETF binary frame.

### Server: configure the socket's serializer

```elixir
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", MyAppWeb.RoomChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
```

```elixir
# in the endpoint
socket "/socket", MyAppWeb.UserSocket,
  websocket: [serializer: [{Flick.Socket.Serializer, "~> 2.0.0"}]]
```

### Client: pass `encode`/`decode` to `Socket`

`flick_channel_serializer.js` is vendored by `mix flick.install --channels`
(see `priv/flick_channel_serializer.js`) and exposes
`window.FlickChannelSerializer`, built on top of `window.Flick`:

```javascript
import {Socket} from "phoenix"

const socket = new Socket("/socket", {
  encode: FlickChannelSerializer.encode,
  decode: FlickChannelSerializer.decode
})

socket.connect()

const channel = socket.channel("room:lobby", {})
channel.join()
  .receive("ok", () => {
    channel.push("echo", {message: "hi", values: [1, 2, 3]})
      .receive("ok", (reply) => console.log(reply))
  })
```

No special `vsn` is needed — `Phoenix.Socket`'s default client `vsn`
(`"2.0.0"`) already satisfies the `"~> 2.0.0"` serializer requirement above.

### Caveats

- `join_ref`, `ref`, `topic`, and `event` are always normalized to/from
  plain strings on both ends.
- The `payload`, however, is encoded/decoded as-is by `flick.js`/`:erlang`,
  so the same caveats as the raw WebSocket integration apply: JS strings
  inside a payload decode to Erlang **charlists** (and conversely, Erlang
  binaries decode to `ErlBinary` on the client — see "Guidelines / Gotchas"
  above). `flick_channel_serializer.js` wraps outgoing payloads with
  `Flick.map(...)` so they always encode as Erlang maps, even with a single
  key.

## Related

- [flick.js](priv/flick.js) — the client-side ETF encoder/decoder, vendored
  from [erlb.js](https://github.com/saleyn/erlb.js).
- [flick_channel_serializer.js](priv/flick_channel_serializer.js) — Phoenix
  Channels ETF serializer for the JS client, pairing with
  `Flick.Socket.Serializer`.

## JS Unit Tests

`test/js/flick-test.js` contains QUnit test cases for `flick.js` covering
encoding, decoding, and stringification. Serve the `test/js` directory and
open `flick-test.html` in a browser:

```bash
cd test/js
python3 -m http.server 8000
```

Then open `http://localhost:8000/flick-test.html`.
