defmodule Flick.ChannelsEtfSerializerTest do
  @moduledoc """
  End-to-end coverage for `Flick.Socket.Serializer` and
  `priv/flick_channel_serializer.js` against a real `Phoenix.Channel`.

  Starts a `Phoenix.Endpoint` (`Flick.Test.EtfEndpoint`) whose `/socket`
  websocket transport is configured with `Flick.Socket.Serializer`, mounted
  under Bandit. A Node.js script (`test/support/echo_channel_client.js`)
  loads `flick.js`, `flick_channel_serializer.js` and the Phoenix JS client,
  connects with `Flick.ChannelSerializer`'s `encode`/`decode`, joins
  "room:lobby", pushes an "echo" event with an ETF-encoded payload, and
  prints the JSON-encoded reply it receives.

  ## Sequence diagram

  ```mermaid
  sequenceDiagram
      participant T as ExUnit test
      participant E as Flick.Test.EtfEndpoint (Bandit)
      participant C as Flick.Test.EchoChannel
      participant N as Node (echo_channel_client.js)

      T->>E: start_link (random port)
      T->>N: spawn node echo_channel_client.js flick.js phoenix.js \
             flick_channel_serializer.js ws://.../socket

      N->>E: WebSocket connect /socket/websocket?vsn=2.0.0
      N->>E: join envelope [join_ref, ref, "room:lobby", "phx_join", {}]
      E->>C: join("room:lobby", payload, socket)
      C->>E: {:ok, socket}
      E->>N: phx_reply envelope (binary ETF)

      N->>E: push envelope [join_ref, ref, "room:lobby", "echo", payload]
      E->>C: handle_in("echo", payload, socket)
      C->>E: {:reply, {:ok, payload}, socket}
      E->>N: phx_reply envelope (binary ETF)

      N->>N: Flick.ChannelSerializer.decode(rawPayload)
      N->>T: print JSON-encoded reply and exit 0

      T->>T: assert reply == %{"status" => "ok", "response" => %{...}}
  ```
  """

  use ExUnit.Case

  setup_all do
    Application.put_env(:flick, Flick.Test.EtfEndpoint,
      pubsub_server: Flick.Test.PubSub,
      server: false,
      secret_key_base: String.duplicate("a", 64)
    )

    {:ok, _pubsub} = Phoenix.PubSub.Supervisor.start_link(name: Flick.Test.PubSub)
    {:ok, _endpoint} = Flick.Test.EtfEndpoint.start_link()

    previous_level = Logger.level()
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: previous_level) end)

    {:ok, bandit_pid} =
      Bandit.start_link(plug: Flick.Test.EtfEndpoint, port: 0, scheme: :http)

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit_pid)

    on_exit(fn -> Supervisor.stop(bandit_pid) end)

    {:ok, port: port}
  end

  test "a Phoenix.Channel join/push/reply round trip via ETF", %{port: port} do
    flick_js = Application.app_dir(:flick, "priv/flick.js")
    channel_serializer_js = Application.app_dir(:flick, "priv/flick_channel_serializer.js")
    phoenix_js = Application.app_dir(:phoenix, "priv/static/phoenix.js")

    client_script = Path.join(__DIR__, "../support/echo_channel_client.js")
    url = "ws://127.0.0.1:#{port}/socket"

    {output, exit_code} =
      System.cmd(
        "node",
        [client_script, flick_js, phoenix_js, channel_serializer_js, url],
        stderr_to_stdout: true
      )

    assert exit_code == 0, "echo_channel_client.js failed:\n#{output}"

    reply = JSON.decode!(String.trim(output))

    assert reply == %{
             "message" => "hello from client",
             "values" => <<1, 2, 3>>
           }
  end
end
