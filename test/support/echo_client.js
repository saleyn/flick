// Loads the vendored flick.js produced by `mix flick.install`, connects to
// the echo WebSocket server, decodes the server's greeting with
// `Flick.decode`, verifies its contents, then re-encodes it and echoes it
// back to the server as a binary frame.
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

const [, , flickJsPath, url] = process.argv;

vm.runInThisContext(fs.readFileSync(flickJsPath, "utf8"));

const ws = new WebSocket(url);
ws.binaryType = "arraybuffer";

ws.onmessage = (event) => {
  const decoded = Flick.decode(event.data);

  const message = String.fromCharCode(...decoded.message.value);

  assert.strictEqual(decoded.type.value, "greeting");
  assert.strictEqual(message, "hello from server");
  assert.deepStrictEqual(decoded.values, "\x01\x02\x03");

  const reply = Flick.toArrayBuffer(Flick.bufferToArray(Flick.encode(decoded)));
  ws.send(reply);
  ws.close();

  console.log("ok");
};

ws.onerror = (event) => {
  console.error("WebSocket error:", event.message || event);
  process.exit(1);
};
