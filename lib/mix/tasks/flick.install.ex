defmodule Mix.Tasks.Flick.Install do
  @moduledoc """
  Installs flick.js for use as the binary WebSocket (ETF) encoder/decoder
  in a Phoenix project.

  This copies the `flick.js` bundled with the `:flick` dependency, vendors
  it under `assets/vendor/flick.js`, copies it to
  `priv/static/assets/js/flick.js` so it is served as a static asset, and
  adds a `<script>` tag for it to the root layout (before `app.js`) so
  `window.Flick` is available globally.

  See the project README for the full integration guide.

  ## Usage

      mix flick.install
      mix flick.install --layout lib/my_app_web/components/layouts/root.html.heex
      mix flick.install --channels
      mix flick.install --minify

  ## Options

    * `--layout` - path to the root layout file to patch with the
      `<script>` tag. Defaults to
      `lib/<app>_web/components/layouts/root.html.heex`.
    * `--skip-layout` - vendor the file but do not modify the root layout.
    * `--channels` - also vendor `flick_channel_serializer.js` to
      `assets/vendor/`, for projects using `Flick.Socket.Serializer` with
      Phoenix Channels.
    * `--minify` - minify the installed JS files using the esbuild binary
      from the host application's `:esbuild` dependency. Requires that
      `:esbuild` is listed as a dependency and its binary has been installed
      (`mix esbuild.install`).
  """
  @shortdoc "Installs flick.js for binary (ETF) WebSocket support"
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [layout: :string, skip_layout: :boolean, channels: :boolean, minify: :boolean]
      )

    source = read_priv_file!("flick.js")

    vendor_path = Path.join(["assets", "vendor", "flick.js"])
    static_path = Path.join(["priv", "static", "assets", "js", "flick.js"])

    write_file!(vendor_path, source)
    write_file!(static_path, source)

    if opts[:minify] do
      minify_file!(static_path)
    end

    channel_serializer_path =
      if opts[:channels] do
        path = Path.join(["assets", "vendor", "flick_channel_serializer.js"])
        write_file!(path, read_priv_file!("flick_channel_serializer.js"))
        if opts[:minify], do: minify_file!(path)
        path
      end

    unless opts[:skip_layout] do
      layout_path = opts[:layout] || default_layout_path()
      patch_layout!(layout_path)
    end

    Mix.shell().info("""

    flick.js installed.

      #{vendor_path}  (source of truth)
      #{static_path}  (served as a static asset)
    #{if channel_serializer_path, do: "  #{channel_serializer_path}  (Phoenix Channels ETF serializer)\n"}
    Next steps:
      1. Run `mix assets.deploy` (or restart the dev server) to pick up the
         new static file.
      2. Define a `WebSock` module that encodes maps with
         `:erlang.term_to_binary/1` and pushes `{:binary, payload}` frames.
      3. In your JS hook, set `ws.binaryType = "arraybuffer"` and decode
         incoming frames with `window.Flick.decode(event.data)`.

    See the flick README for the full guide and gotchas.
    """)
  end

  defp minify_file!(path) do
    unless Code.ensure_loaded?(Esbuild) do
      Mix.raise("""
      --minify requires the :esbuild dependency. Add it to your mix.exs:

          {:esbuild, "~> 0.8", runtime: Mix.env() == :dev}

      Then run `mix esbuild.install` and retry.
      """)
    end

    bin = apply(Esbuild, :bin_path, [])

    unless File.exists?(bin) do
      Mix.raise("esbuild binary not found at #{bin}. Run `mix esbuild.install` first.")
    end

    case System.cmd(bin, [path, "--minify", "--outfile=#{path}", "--allow-overwrite"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Mix.shell().info("* minified #{path}")

      {output, code} ->
        Mix.raise("esbuild exited with #{code} while minifying #{path}:\n#{output}")
    end
  end

  defp read_priv_file!(name) do
    path = Application.app_dir(:flick, "priv/#{name}")

    case File.read(path) do
      {:ok, source} ->
        source

      {:error, reason} ->
        Mix.raise("Failed to read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp write_file!(path, contents) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, contents)
    Mix.shell().info("* wrote #{path}")
  end

  defp default_layout_path do
    web_module =
      Mix.Project.config()[:app]
      |> to_string()
      |> Kernel.<>("_web")

    Path.join(["lib", web_module, "components", "layouts", "root.html.heex"])
  end

  defp patch_layout!(layout_path) do
    unless File.exists?(layout_path) do
      Mix.shell().info("""

      ! Could not find root layout at #{layout_path} — skipping automatic
        <script> tag insertion. Add the following manually, before your
        app.js script tag:

          <script src={~p"/assets/js/flick.js"}></script>
      """)

      :ok
    else
      contents = File.read!(layout_path)

      cond do
        String.contains?(contents, "/assets/js/flick.js") ->
          Mix.shell().info("* #{layout_path} already references flick.js, leaving unchanged")

        String.contains?(contents, ~s|~p"/assets/js/app.js"|) ->
          updated =
            String.replace(
              contents,
              ~r/^([ \t]*)(<script[^>]*src=\{~p"\/assets\/js\/app\.js"\}.*)$/m,
              ~s(\\1<script src={~p"/assets/js/flick.js"}></script>\n\\1\\2)
            )

          File.write!(layout_path, updated)
          Mix.shell().info("* patched #{layout_path} with flick.js <script> tag")

        true ->
          Mix.shell().info("""

          ! Could not find an app.js <script> tag in #{layout_path} —
            skipping automatic insertion. Add the following manually, before
            your app.js script tag:

              <script src={~p"/assets/js/flick.js"}></script>
          """)
      end
    end
  end
end
