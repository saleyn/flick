// Phoenix `Socket`-compatible serializer that encodes the whole Channels
// envelope (`join_ref`, `ref`, `topic`, `event`, `payload`) as a single
// Erlang External Term Format (ETF) binary frame, using `Flick.encode` /
// `Flick.decode`. Pairs with `Flick.Socket.Serializer` on the server.
//
// Usage:
//
//   import {Socket} from "phoenix"
//   import FlickChannelSerializer from "./flick_channel_serializer"
//
//   const socket = new Socket("/socket", {
//     encode: FlickChannelSerializer.encode,
//     decode: FlickChannelSerializer.decode
//   })
//
// Requires `flick.js` (`window.Flick`) to be loaded first.
(function (global) {
    function fromErlBinary(value) {
        return (value instanceof ErlBinary)
            ? String.fromCharCode.apply(String, value.value)
            : value;
    }

    function fromErlAtom(value) {
        return (value instanceof ErlAtom) ? value.value : value;
    }

    // `phx_reply` payloads come over the wire as `%{status: :ok | :error,
    // response: ...}`, decoding to `{status: ErlAtom, response: ...}`. The
    // Phoenix JS client expects `status` to be the plain string "ok"/"error".
    function normalizePayload(event, payload) {
        if (event !== "phx_reply") return payload;

        return {
            status:   fromErlAtom(payload.status),
            response: payload.response
        };
    }

    var FlickChannelSerializer = {
        encode: function (msg, callback) {
            var envelope = [
                msg.join_ref,
                msg.ref,
                msg.topic,
                msg.event,
                Flick.map(msg.payload || {})
            ];

            return callback(Flick.encode(envelope));
        },

        decode: function (rawPayload, callback) {
            var envelope = Flick.decode(rawPayload);
            var event    = fromErlBinary(envelope[3]);

            return callback({
                join_ref: fromErlBinary(envelope[0]),
                ref:      fromErlBinary(envelope[1]),
                topic:    fromErlBinary(envelope[2]),
                event:    event,
                payload:  normalizePayload(event, envelope[4])
            });
        }
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = FlickChannelSerializer;
    }
    global.FlickChannelSerializer = FlickChannelSerializer;
})(typeof window !== 'undefined' ? window : globalThis);
