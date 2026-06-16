// Loads the vendored flick.js, the Flick channel serializer, and the
// Phoenix JS client, joins "room:lobby" on a Flick.Socket.Serializer-backed
// Phoenix.Socket, pushes an "echo" event with an ETF payload, and prints the
// reply payload as JSON so the test can assert on it.
const fs = require("fs");
const vm = require("vm");

const [, , flickJsPath, phoenixJsPath, channelSerializerPath, url] = process.argv;

vm.runInThisContext(fs.readFileSync(flickJsPath, "utf8"));
vm.runInThisContext(fs.readFileSync(phoenixJsPath, "utf8"));
vm.runInThisContext(fs.readFileSync(channelSerializerPath, "utf8"));

const socket = new Phoenix.Socket(url, {
  transport: WebSocket,
  encode: FlickChannelSerializer.encode,
  decode: FlickChannelSerializer.decode
});

socket.onError((error) => {
  console.error("socket error:", error.message || error);
  process.exit(1);
});

socket.connect();

const channel = socket.channel("room:lobby", {});

channel.join()
  .receive("ok", () => {
    channel.push("echo", {message: "hello from client", values: [1, 2, 3]})
      .receive("ok", (reply) => {
        console.log(JSON.stringify(reply));
        socket.disconnect();
      });
  })
  .receive("error", (reason) => {
    console.error("join error:", JSON.stringify(reason));
    process.exit(1);
  });
