defmodule Flick.InstallAndRoundtripTest do
  @moduledoc """
  End-to-end coverage for `mix flick.install` against a sample Phoenix-style
  project, and for the resulting `flick.js` as a real WebSocket client.

  * "mix flick.install vendors flick.js and patches the root layout" runs the
    install task against a temp project containing only a root layout file,
    and checks that `flick.js` is vendored to `assets/vendor/flick.js` and
    `priv/static/assets/js/flick.js`, and that the layout gets a `<script>`
    tag for `flick.js` inserted before the `app.js` tag.

  * "mix flick.install --channels also vendors flick-channel.js"
    runs the install task with `--skip-layout --channels` and checks that
    `priv/flick-channel.js` is additionally vendored to
    `assets/vendor/flick-channel.js`.

  * "a JS client decodes a server ETF message and echoes it back" vendors
    `flick.js` (via `--skip-layout`), starts a real Bandit/WebSock server
    that pushes an `:erlang.term_to_binary/1`-encoded greeting map, and runs
    a Node.js script (`test/support/echo_client.js`) that loads the vendored
    `flick.js`, decodes the greeting with `Flick.decode`, asserts its
    contents, re-encodes it with `Flick.encode`, and sends it back as a
    binary frame. The test then asserts the server received and correctly
    decoded that echoed message — proving the full
    encode/push/decode/re-encode/echo/decode round trip works with the
    artifact produced by `mix flick.install`.

  ## Sequence diagram (last test)

  ```mermaid
  sequenceDiagram
      participant T as ExUnit test
      participant I as Mix.Tasks.Flick.Install
      participant B as Bandit (EchoRouter/EchoSocket)
      participant N as Node (echo_client.js / Flick)

      T->>I: run(["--skip-layout"]) in tmp_dir
      I->>T: writes priv/static/assets/js/flick.js

      T->>B: start_link (random port)
      T->>N: spawn node echo_client.js flick.js ws://.../ws

      N->>B: WebSocket connect /ws
      B->>B: init/1 sends self() :send_greeting
      B->>N: {:binary, term_to_binary(%{type: :greeting, ...})}

      N->>N: Flick.decode(event.data)
      N->>N: assert type/message/values
      N->>N: Flick.encode(decoded)
      N->>B: send binary frame (echo)
      N->>T: print "ok" and exit 0

      B->>B: handle_in/2 binary_to_term(payload)
      B->>T: send {:echo, decoded_map}

      T->>T: assert_receive {:echo, %{"type" => :greeting, ...}}
  ```
  """

  use ExUnit.Case

  import ExUnit.CaptureIO

  @moduletag :integration

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "flick_install_test_#{System.unique_integer([:positive])}")

    layout_path = Path.join(tmp_dir, "lib/sample_app_web/components/layouts/root.html.heex")

    File.mkdir_p!(Path.dirname(layout_path))

    File.write!(layout_path, """
    <!DOCTYPE html>
    <html>
      <body>
        {@inner_content}
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
        </script>
      </body>
    </html>
    """)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir, layout_path: layout_path}
  end

  test "mix flick.install vendors flick.js and patches the root layout", %{
    tmp_dir: tmp_dir,
    layout_path: layout_path
  } do
    install_output =
      capture_io(fn ->
        File.cd!(tmp_dir, fn ->
          Mix.Tasks.Flick.Install.run(["--layout", layout_path, "--yes"])
        end)
      end)

    assert install_output =~ "write   assets/vendor/flick.min.js.gz"
    assert install_output =~ "write   priv/static/assets/js/flick.min.js.gz"
    assert install_output =~ "patch   #{layout_path}"

    vendored_source = Application.app_dir(:flick, "priv/flick.min.js.gz") |> File.read!()

    vendor_path = Path.join(tmp_dir, "assets/vendor/flick.min.js.gz")
    static_path = Path.join(tmp_dir, "priv/static/assets/js/flick.min.js.gz")

    assert File.read!(vendor_path) == vendored_source
    assert File.read!(static_path) == vendored_source

    layout = File.read!(layout_path)
    assert layout =~ ~s(<script src={~p"/assets/js/flick.min.js"}></script>)

    # the flick.js script tag must come before the app.js one
    {flick_pos, _} = :binary.match(layout, "/assets/js/flick.min.js")
    {app_pos,   _} = :binary.match(layout, "/assets/js/app.js")
    assert flick_pos < app_pos
  end

  test "mix flick.install --channels also vendors flick-channel.js", %{
    tmp_dir: tmp_dir
  } do
    install_output =
      capture_io(fn ->
        File.cd!(tmp_dir, fn ->
          Mix.Tasks.Flick.Install.run(["--skip-layout", "--channels", "--yes"])
        end)
      end)

    assert install_output =~ "write   assets/vendor/flick.min.js.gz"
    assert install_output =~ "write   assets/vendor/flick-channel.min.js.gz"

    vendored_source =
      Application.app_dir(:flick, "priv/flick-channel.min.js.gz") |> File.read!()

    serializer_path = Path.join(tmp_dir, "assets/vendor/flick-channel.min.js.gz")
    assert File.read!(serializer_path) == vendored_source
  end

  test "a JS client decodes a server ETF message and echoes it back", %{tmp_dir: tmp_dir} do
    install_output =
      capture_io(fn ->
        File.cd!(tmp_dir, fn ->
          Mix.Tasks.Flick.Install.run(["--skip-layout", "--yes"])
        end)
      end)

    assert install_output =~ "write   priv/static/assets/js/flick.min.js.gz"
    refute install_output =~ "patch"

    static_gz_path = Path.join(tmp_dir, "priv/static/assets/js/flick.min.js.gz")
    assert File.exists?(static_gz_path)

    # Node.js needs the uncompressed JS; use the priv source directly.
    static_path = Application.app_dir(:flick, "priv/flick.js")

    :persistent_term.put({Flick.Test.EchoRouter, :test_pid}, self())

    previous_level = Logger.level()
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: previous_level) end)

    {:ok, bandit_pid} =
      Bandit.start_link(plug: Flick.Test.EchoRouter, port: 0, scheme: :http)

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit_pid)

    client_script = Path.join(__DIR__, "../support/echo_client.js")
    url = "ws://127.0.0.1:#{port}/ws"

    {output, exit_code} =
      System.cmd("node", [client_script, static_path, url], stderr_to_stdout: true)

    assert exit_code == 0, "echo_client.js failed:\n#{output}"
    assert String.trim(output) == "ok"

    assert_receive {:echo, echoed}, 5_000

    assert echoed == %{
             "type" => :greeting,
             "message" => "hello from server",
             "values" => [1, 2, 3]
           }

    Supervisor.stop(bandit_pid)
  end
end
