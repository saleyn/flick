![Flick](assets/flick-logo.png)

[![build](https://github.com/saleyn/flick/actions/workflows/ci.yml/badge.svg)](https://github.com/saleyn/flick/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/flick.svg)](https://hex.pm/packages/flick)
[![Hex.pm](https://img.shields.io/hexpm/dt/flick.svg)](https://hex.pm/packages/flick)

Binary Erlang External Term Format (ETF) WebSocket transport for Phoenix,
decoded on the client with [flick.js](priv/flick.js).

The project is an evolution of the JavaScript ETF codec implemementation
[erlb.js](https://github.com/saleyn/erlb.js) migrated to be used by Phoenix
applications.

## Raw WebSocket vs Phoenix Channels — which do you need?

Phoenix ships two WebSocket abstractions that serve different purposes:

**Raw WebSocket (`WebSock` behaviour)** is a plain, low-overhead connection.
Your server module receives frames and pushes `{:binary, payload}` replies
directly. There is no topic system, no join/leave lifecycle, and no built-in
broadcast. This is the right choice when you control both ends of the
connection and want minimal latency — for example, streaming live market data
or sensor feeds to a single client page.

**Phoenix Channels** layer a pub/sub protocol on top of a WebSocket. A single
connection is multiplexed across named topics; clients join and leave topics,
and the server can broadcast to all subscribers via `Phoenix.PubSub`. The
tradeoff is that every message is wrapped in a JSON envelope
(`join_ref`, `ref`, `topic`, `event`, `payload`). This is the right choice
when you already use Channels for other features and want ETF to replace only
the serialization layer.

**Flick supports both.** The default `mix flick.install` sets up a raw
`WebSock` connection. Channels support can be included from the start:

```bash
mix flick.install --channels
```

or added to an existing installation without re-running the boilerplate
generator:

```bash
mix flick.install --channels --no-boilerplate
```

Either way, only `flick-channel.min.js.gz` is vendored — the server and
client Channels configuration is always done manually. See
[Phoenix Channels over ETF](#phoenix-channels-over-etf) for the full
configuration.

## Features

- **Raw WebSocket + ETF** — push `{:binary, etf_bytes}` frames directly via
  the `WebSock` behaviour; no JSON serialization, no Channels overhead.
- **Phoenix Channels support** — `Flick.Socket.Serializer` and
  `flick-channel.js` swap out Phoenix's default JSON channel
  serializer with an ETF one, keeping full Channels semantics (topics, join,
  push, broadcast).
- **Zero-dependency client** — `flick.js` is a single self-contained script
  exposing `window.Flick`; no npm package or bundler step required.
- **`mix flick.install`** — one command vendors the pre-minified, pre-gzipped
  `flick.min.js.gz`, patches the root layout, and generates all server and
  client boilerplate. No esbuild or npm step required.
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

---

## Step-by-Step: Adding an ETF WebSocket to a New Project

> **Prefer a worked example?** The [example/TUTORIAL.md](example/TUTORIAL.md)
> walks through a concrete Phoenix stock-ticker app, migrating it from HTTP JSON
> polling to a flick ETF WebSocket step by step, with before/after diffs for
> every changed file.

### 1. Add `websock_adapter` to your dependencies

`mix flick.install` checks that `:websock_adapter` is listed in your `mix.exs`
and exits with an error if it is missing. Typically Phoenix >= 1.7 pulls it in
transitively (via `bandit`), but it must appear explicitly so the check passes:

```elixir
{:websock_adapter, "~> 0.5"}
```

Then run:

```bash
mix deps.get
```

### 2. Run `mix flick.install`

```bash
mix flick.install                                      # defaults
mix flick.install --module TickerSocket --path /ws/ticker
mix flick.install --channels                           # also install flick-channel.js
mix flick.install --yes                                # skip confirmation prompt
```

The installer prints a plan of every change and asks for confirmation before
writing anything. It handles all remaining setup steps automatically:

| What                                    | How                                          |
|-----------------------------------------|----------------------------------------------|
| Vendor `flick.min.js.gz`                | written to `assets/vendor/` and `priv/static/assets/js/` |
| Add `<script>` tag to root layout       | inserted before `app.js`                     |
| `WebSock` module skeleton               | created at `lib/<app>_web/my_socket.ex`      |
| Upgrade controller                      | created at `lib/<app>_web/my_socket_controller.ex` |
| Router route                            | `get "/ws", ...` inserted into `router.ex`   |
| Starter JS hook                         | appended to `assets/js/app.js`               |

All steps are idempotent — re-running is safe.

`Plug.Static` serves `.gz` files automatically when `gzip: true` is set —
that is the Phoenix default, so no extra configuration is needed.

Available options (`mix help flick.install` for the full list):

- `--module NAME` — module name suffix, default `MySocket`
- `--path PATH` — WebSocket URL path, default `/ws`
- `--layout PATH` — non-default root layout file
- `--skip-layout` — skip the `<script>` tag patch
- `--channels` — also vendor `flick-channel.min.js.gz`
- `--no-boilerplate` — vendor JS and patch layout only (skip the server/JS boilerplate)
- `--yes` — skip the confirmation prompt

### 3. Fill in your business logic

After `mix flick.install` runs, two files need your application-specific code:

**`lib/<app>_web/my_socket.ex`** — generated skeleton, edit `handle_info` to push
real data:

```elixir
@impl WebSock
def handle_info(:send_snapshot, state) do
  payload = :erlang.term_to_binary(%{type: :snapshot, data: []})
  {:push, {:binary, payload}, state}
end
```

See [Guidelines: server-side encoding](#1-server-side---encode-with-erlangtermtobinary1)
for what types are safe to encode.

**`assets/js/app.js`** — the appended starter hook opens the socket and logs
messages. Replace the `console.log` with your actual dispatch logic:

```javascript
_flickWs.onmessage = (event) => {
  const msg  = window.Flick.decode(event.data)
  const type = msg.type && msg.type.value ? msg.type.value : String(msg.type)

  switch (type) {
    case "snapshot": /* handle msg.data */ break
    default: console.warn("Unknown message type:", type)
  }
}
```

See [Guidelines: client-side decoding](#2-atoms-decode-to-erlatom-objects-not-strings)
for atom handling and the `nil`/`null` mapping.

### 4. Restart and test

```bash
mix assets.deploy   # or just restart the dev server
```

Open the page and check the browser console — you should see the WebSocket
connecting and decoded messages appearing as plain JS objects, with atom fields
as `ErlAtom{value: "..."}`.

---

## Guidelines

These apply whether you used `mix flick.install` or wired things up manually.

### 1. Server side - encode with `:erlang.term_to_binary/1`

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

### 2. Client side - atoms decode to `ErlAtom` objects, not strings

`flick.js` decodes Erlang atoms (e.g. `:snapshot`, `:tick`) as `ErlAtom{value:
"snapshot"}` objects, **not** plain JS strings. Always compare via `.value`:

```javascript
const msg  = window.Flick.decode(event.data)
const type = msg.type && msg.type.value ? msg.type.value : String(msg.type)

if (type === "tick") { /* ... */ }
```

### 3. Client side - Elixir `nil` decodes to JS `null`

`flick.js`'s `decode_atom` maps the Erlang/Elixir atom `nil` directly to JS
`null` (alongside its existing `true`/`false`/`undefined`/`null` atom
mappings), and `encode_object` maps JS `null` back to the atom `nil` when
encoding. This means `nil` values round-trip without any workaround:

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

`mix flick.install` adds the `<script>` tag and appends the starter hook
automatically. If you are wiring things up manually:

- Add `<script src={~p"/assets/js/flick.min.js"}></script>` before `app.js`
  in the root layout so `window.Flick` is available globally.
- Set `ws.binaryType = "arraybuffer"` before the socket connects.
- Decode each frame with `window.Flick.decode(event.data)`.

```javascript
const ws = new WebSocket(url)
ws.binaryType = "arraybuffer"

ws.onmessage = (event) => {
  const msg = window.Flick.decode(event.data)
  // ... dispatch on msg.type.value
}
```

---

## Manual Wiring (alternative to `mix flick.install`)

If you prefer not to use the installer, here are the equivalent manual steps.

### A. Vendor the JS files

Copy from the `:flick` dependency's `priv/` directory:

```bash
cp deps/flick/priv/flick.min.js.gz assets/vendor/
cp deps/flick/priv/flick.min.js.gz priv/static/assets/js/
```

Add to the root layout, before `app.js`:

```heex
<script src={~p"/assets/js/flick.min.js"}></script>
```

### B. Define the `WebSock` module

```elixir
defmodule MyAppWeb.MySocket do
  @behaviour WebSock

  @impl WebSock
  def init(args), do: {:ok, %{args: args}}

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

### C. Add a controller

```elixir
defmodule MyAppWeb.MySocketController do
  use MyAppWeb, :controller

  def connect(conn, params) do
    WebSockAdapter.upgrade(conn, MyAppWeb.MySocket, params, [])
  end
end
```

### D. Add the router route

```elixir
get "/ws", MySocketController, :connect
```

### E. Add a JS hook

```javascript
const proto = location.protocol === "https:" ? "wss" : "ws"
const ws    = new WebSocket(`${proto}://${location.host}/ws`)
ws.binaryType = "arraybuffer"

ws.onmessage = (event) => {
  const msg  = window.Flick.decode(event.data)
  const type = msg.type && msg.type.value ? msg.type.value : String(msg.type)

  switch (type) {
    case "snapshot": /* handle msg.data */ break
    default: console.warn("Unknown message type:", type)
  }
}
```

---

## Phoenix Channels over ETF

If you'd rather use Phoenix Channels (join/leave, topics, PubSub broadcasts)
instead of a raw `WebSock` socket, `Flick.Socket.Serializer` and
[flick-channel.js](priv/flick-channel.js) replace
Phoenix's default JSON channel serializer with one that encodes the whole
Channels envelope (`join_ref`, `ref`, `topic`, `event`, `payload`) as a
single ETF binary frame.

`mix flick.install --channels` vendors `flick-channel.min.js.gz` in addition
to `flick.min.js.gz`. The server and client must then be configured manually
as shown below — the installer does not generate Channels boilerplate.

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

`flick-channel.js` is vendored by `mix flick.install --channels`
(see `priv/flick-channel.js`) and exposes
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
  binaries decode to `ErlBinary` on the client — see "Guidelines" above).
  `flick-channel.js` wraps outgoing payloads with `Flick.map(...)` so they
  always encode as Erlang maps, even with a single key.

## Related

- [flick.js](priv/flick.js) — the client-side ETF encoder/decoder source,
  vendored from [erlb.js](https://github.com/saleyn/erlb.js).
  Pre-built as [flick.min.js.gz](priv/flick.min.js.gz) (run `make minify` to
  regenerate after editing the source).
- [flick-channel.js](priv/flick-channel.js) — Phoenix
  Channels ETF serializer for the JS client, pairing with
  `Flick.Socket.Serializer`.
  Pre-built as [flick-channel.min.js.gz](priv/flick-channel.min.js.gz).

## JS Unit Tests

`test/js/flick-test.js` contains QUnit test cases for `flick.js` covering
encoding, decoding, and stringification. Serve the `test/js` directory and
open `flick-test.html` in a browser:

```bash
cd test/js
python3 -m http.server 8000
```

Then open `http://localhost:8000/flick-test.html`.

## License

[MIT License](LICENSE)