defmodule Flick.Socket.Serializer do
  @moduledoc """
  A `Phoenix.Socket.Serializer` that encodes the whole Channels envelope
  (`join_ref`, `ref`, `topic`, `event`, `payload`) as a single Erlang
  External Term Format (ETF) binary, paired with `flick.js`'s channel
  serializer on the client.

  Unlike `Phoenix.Socket.V2.JSONSerializer`, every message — regardless of
  payload shape — is sent as a single binary WebSocket frame containing
  `:erlang.term_to_binary([join_ref, ref, topic, event, payload])`.

  ## Usage

  Configure your `Phoenix.Socket` to use this serializer instead of the
  default JSON one:

      transport :websocket, serializer: [{Flick.Socket.Serializer, "~> 2.0.0"}]

  On the client, use `Flick.ChannelSerializer` (vendored alongside
  `flick.js`) when constructing the socket:

      import {Socket} from "phoenix"
      import FlickChannelSerializer from "./flick-channel"

      const socket = new Socket("/socket", {
        encode: FlickChannelSerializer.encode,
        decode: FlickChannelSerializer.decode
      })

  ## Caveats

  `join_ref`, `ref`, `topic`, and `event` are always coerced to/from
  Elixir strings (binaries decode from/encode to JS strings on the wire).
  The `payload`, however, is encoded/decoded as-is by `flick.js`/`:erlang`
  — e.g. JS strings inside a payload decode to Erlang charlists (and
  Erlang binaries decode to `ErlBinary` on the client), the same caveats
  that apply to the raw WebSocket integration described in the README.
  """
  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.{Broadcast, Message, Reply}

  @impl true
  def fastlane!(%Broadcast{} = msg) do
    envelope = [nil, nil, msg.topic, msg.event, msg.payload]
    {:socket_push, :binary, :erlang.term_to_binary(envelope)}
  end

  @impl true
  def encode!(%Reply{} = reply) do
    envelope = [
      reply.join_ref,
      reply.ref,
      reply.topic,
      "phx_reply",
      %{status: reply.status, response: reply.payload}
    ]

    {:socket_push, :binary, :erlang.term_to_binary(envelope)}
  end

  def encode!(%Message{} = msg) do
    envelope = [msg.join_ref, msg.ref, msg.topic, msg.event, msg.payload]
    {:socket_push, :binary, :erlang.term_to_binary(envelope)}
  end

  @impl true
  def decode!(payload, opts) do
    case Keyword.fetch!(opts, :opcode) do
      :binary ->
        [join_ref, ref, topic, event, payload] = :erlang.binary_to_term(payload, [:safe])

        %Message{
          join_ref: to_ref_string(join_ref),
          ref:      to_ref_string(ref),
          topic:    to_string(topic),
          event:    to_string(event),
          payload:  payload
        }
    end
  end

  defp to_ref_string(nil), do: nil
  defp to_ref_string(ref), do: to_string(ref)
end
