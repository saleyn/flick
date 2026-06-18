defmodule Mix.Tasks.Flick.Install do
  @moduledoc """
  Installs flick into a Phoenix project.

  ## What it does

  1. Vendors `flick.min.js.gz` (pre-minified, pre-compressed) to
     `assets/vendor/flick.min.js.gz` and
     `priv/static/assets/js/flick.min.js.gz`.
  2. Patches the root layout to add a `<script>` tag before `app.js`.
  3. Generates a `WebSock` behaviour module skeleton.
  4. Generates an upgrade controller.
  5. Patches `router.ex` with a `get` route for the WebSocket path.
  6. Appends a starter hook to `assets/js/app.js`.

  `Plug.Static` serves `.gz` files automatically when `gzip: true` is set
  (the Phoenix default). No esbuild or runtime minification step required.

  Steps 3–6 are skipped when `--no-boilerplate` is passed.
  All steps are idempotent — re-running is safe.

  ## Usage

      mix flick.install
      mix flick.install --module TickerSocket --path /ws/ticker
      mix flick.install --channels
      mix flick.install --channels --no-boilerplate
      mix flick.install --layout lib/my_app_web/components/layouts/root.html.heex
      mix flick.install --no-boilerplate
      mix flick.install --yes
      mix flick.install --channels --no-plug-crypto

  ## Options

    * `--module` - WebSock module name suffix appended to the `<AppWeb>`
      namespace. Defaults to `MySocket`. Produces `<AppWeb>.MySocket` and
      `<AppWeb>.MySocketController`.
    * `--path` - WebSocket URL path used in the router and JS hook.
      Defaults to `/ws`.
    * `--layout` - path to the root layout file. Defaults to
      `lib/<app>_web/components/layouts/root.html.heex`.
    * `--skip-layout` - skip the root layout patch.
    * `--channels` - also vendor `flick-channel.min.js.gz` for projects
      using `Flick.Socket.Serializer` with Phoenix Channels. Can be combined
      with `--no-boilerplate` to add Channels support to an existing
      installation without re-running the boilerplate generator.
    * `--no-boilerplate` - only vendor the JS files and patch the layout;
      skip steps 3–6.
    * `--no-plug-crypto` - skip the `:plug_crypto` dependency check.
      By default, the installer requires `:plug_crypto` so that
      `Flick.Socket.Serializer.decode!/2` calls
      `Plug.Crypto.non_executable_binary_to_term/2` instead of
      `:erlang.binary_to_term/2` for decoding client payloads, guaranteeing
      rejection of executable terms regardless of OTP version. Pass this
      flag to opt out and rely on `:erlang.binary_to_term/2` with `:safe`
      alone.
    * `--yes` - apply all changes without prompting for confirmation.
  """
  @shortdoc "Installs flick into a Phoenix project"
  use Mix.Task

  @js_name     "flick.min.js.gz"
  @vendor_name "flick.min.js.gz"

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          layout: :string,
          skip_layout: :boolean,
          channels: :boolean,
          no_boilerplate: :boolean,
          module: :string,
          path: :string,
          plug_crypto: :boolean,
          yes: :boolean
        ]
      )

    check_websock_adapter!()
    check_plug_crypto!(opts[:plug_crypto])

    app_name   = Mix.Project.config()[:app] |> to_string()
    web_module = Macro.camelize(app_name) <> "Web"
    mod_suffix = opts[:module] || "MySocket"
    ws_path    = opts[:path]   || "/ws"
    ctrl_suffix = mod_suffix <> "Controller"

    vendor_path  = Path.join(["assets", "vendor", @vendor_name])
    static_path  = Path.join(["priv", "static", "assets", "js", @js_name])
    layout_path  = opts[:layout] || default_layout_path(app_name)
    socket_file  = web_lib_path(app_name, module_to_filename(mod_suffix))
    ctrl_file    = web_lib_path(app_name, module_to_filename(ctrl_suffix))
    router_file  = web_lib_path(app_name, "router.ex")
    app_js       = Path.join(["assets", "js", "app.js"])
    route_line   = ~s(    get "#{ws_path}", #{web_module}.#{ctrl_suffix}, :connect)

    channel_serializer_path =
      if opts[:channels],
        do: Path.join(["assets", "vendor", "flick-channel.min.js.gz"])

    # ------------------------------------------------------------------
    # Plan
    # ------------------------------------------------------------------
    plan = []

    plan = plan ++ [{:write, vendor_path, :flick_js}]
    plan = plan ++ [{:write, static_path, :flick_js}]

    plan =
      if channel_serializer_path,
        do: plan ++ [{:write, channel_serializer_path, :channel_serializer}],
        else: plan

    plan =
      if opts[:skip_layout],
        do: plan,
        else: plan ++ [plan_layout(layout_path)]

    plan =
      if opts[:no_boilerplate],
        do: plan,
        else:
          plan ++
            [
              plan_new_file(socket_file, "WebSock module",
                generate_socket_content(web_module, mod_suffix)),
              plan_new_file(ctrl_file, "controller",
                generate_controller_content(web_module, mod_suffix, ctrl_suffix)),
              plan_router(router_file, ws_path, route_line),
              plan_app_js(app_js)
            ]

    print_plan(plan, web_module, mod_suffix, ctrl_suffix, ws_path, opts)

    unless opts[:yes] do
      unless Mix.shell().yes?("\nProceed?") do
        Mix.shell().info("Aborted.")
        exit(:normal)
      end
    end

    # ------------------------------------------------------------------
    # Execute
    # ------------------------------------------------------------------
    Enum.each(plan, fn
      {:write, path, :flick_js} ->
        write_file!(path, read_priv_file!(@js_name))

      {:write, path, :channel_serializer} ->
        write_file!(path, read_priv_file!("flick-channel.min.js.gz"))

      {:patch_layout, path} ->
        patch_layout!(path)

      {:skip, _path, _reason} ->
        :ok

      {:warn, msg} ->
        Mix.shell().info("\n! #{msg}")

      {:create, path, content} ->
        path |> Path.dirname() |> File.mkdir_p!()
        File.write!(path, content)
        Mix.shell().info("* wrote #{path}")

      {:patch_router, path} ->
        patch_router!(path, route_line, ws_path)

      {:patch_app_js, path} ->
        patch_app_js!(path, ws_path)
    end)

    Mix.shell().info("""

    Done. Next steps:
      1. Ensure Plug.Static has `gzip: true` in your endpoint (Phoenix default).
      2. Run `mix assets.deploy` or restart the dev server.
      3. Edit #{socket_file} to push ETF frames.
    """)
  end

  # ------------------------------------------------------------------
  # Planning helpers
  # ------------------------------------------------------------------

  defp plan_layout(path) do
    cond do
      not File.exists?(path) ->
        {:warn, "root layout not found at #{path} — add the <script> tag manually"}

      File.read!(path) |> String.contains?("/assets/js/flick.min.js") ->
        {:skip, path, "layout already references flick.min.js"}

      File.read!(path) |> String.contains?(~s|~p"/assets/js/app.js"|) ->
        {:patch_layout, path}

      true ->
        {:warn, "no app.js <script> found in #{path} — add the <script> tag manually"}
    end
  end

  defp plan_new_file(path, label, content) do
    if File.exists?(path),
      do: {:skip, path, "#{label} already exists"},
      else: {:create, path, content}
  end

  defp plan_router(path, ws_path, route_line) do
    cond do
      not File.exists?(path) ->
        {:warn, "router not found at #{path} — add this route manually:\n    #{route_line}"}

      File.read!(path) |> String.contains?(~s|"#{ws_path}"|) ->
        {:skip, path, "route for #{ws_path} already present"}

      File.read!(path) |> String.contains?("scope ") ->
        {:patch_router, path}

      true ->
        {:warn, "no scope block found in #{path} — add this route manually:\n    #{route_line}"}
    end
  end

  defp plan_app_js(path) do
    cond do
      not File.exists?(path) ->
        {:warn, "#{path} not found — add the flick JS hook manually (see README step 6)"}

      File.read!(path) |> String.contains?("flick WebSocket") ->
        {:skip, path, "flick hook already present"}

      true ->
        {:patch_app_js, path}
    end
  end

  defp print_plan(plan, web_module, mod_suffix, ctrl_suffix, ws_path, opts) do
    Mix.shell().info("""

    App:        #{Mix.Project.config()[:app]}  (#{web_module})
    WebSock:    #{web_module}.#{mod_suffix}
    Controller: #{web_module}.#{ctrl_suffix}
    WS path:    #{ws_path}
    #{if opts[:channels], do: "Mode:       Phoenix Channels\n", else: ""}
    Planned actions:
    """)

    Enum.each(plan, fn
      {:write, path, _}       -> Mix.shell().info("  write   #{path}")
      {:patch_layout, path}   -> Mix.shell().info("  patch   #{path}  (add <script> tag)")
      {:patch_router, path}   -> Mix.shell().info("  patch   #{path}  (insert get route)")
      {:patch_app_js, path}   -> Mix.shell().info("  append  #{path}  (flick WebSocket hook)")
      {:create, path, _}      -> Mix.shell().info("  create  #{path}")
      {:skip, path, reason}   -> Mix.shell().info("  skip    #{path}  (#{reason})")
      {:warn, msg}            -> Mix.shell().info("  warn    #{msg}")
    end)
  end

  # ------------------------------------------------------------------
  # Execution helpers
  # ------------------------------------------------------------------

  defp patch_router!(router_file, route_line, ws_path) do
    contents = File.read!(router_file)

    updated =
      String.replace(
        contents,
        ~r/^([ \t]*scope\b[^\n]*\bdo[ \t]*)$/m,
        "\\1\n#{route_line}",
        global: false
      )

    File.write!(router_file, updated)
    Mix.shell().info("* patched #{router_file} with route for #{ws_path}")
  end

  defp patch_app_js!(app_js, ws_path) do
    hook = """

    // flick WebSocket — #{ws_path}
    const _flickProto = location.protocol === "https:" ? "wss" : "ws"
    const _flickUrl   = `${_flickProto}://${location.host}#{ws_path}`
    const _flickWs    = new WebSocket(_flickUrl)
    _flickWs.binaryType = "arraybuffer"
    _flickWs.onmessage = (event) => {
      const msg  = window.Flick.decode(event.data)
      const type = msg.type && msg.type.value ? msg.type.value : String(msg.type)
      console.log("flick message:", type, msg)
    }
    """

    File.write!(app_js, hook, [:append])
    Mix.shell().info("* appended flick hook to #{app_js}")
  end

  defp patch_layout!(layout_path) do
    contents = File.read!(layout_path)

    updated =
      String.replace(
        contents,
        ~r/^([ \t]*)(<script[^>]*src=\{~p"\/assets\/js\/app\.js"\}.*)$/m,
        ~s(\\1<script src={~p"/assets/js/flick.min.js"}></script>\n\\1\\2)
      )

    File.write!(layout_path, updated)
    Mix.shell().info("* patched #{layout_path} with flick.min.js <script> tag")
  end

  defp check_websock_adapter! do
    deps = Mix.Project.config()[:deps] || []

    unless Enum.any?(deps, fn dep -> elem(dep, 0) == :websock_adapter end) do
      Mix.raise("""
      :flick requires the :websock_adapter dependency. Add it to your mix.exs:

          {:websock_adapter, "~> 0.5"}

      Then run `mix deps.get` and retry.
      """)
    end
  end

  defp check_plug_crypto!(false), do: :ok

  defp check_plug_crypto!(_) do
    deps = Mix.Project.config()[:deps] || []

    unless Enum.any?(deps, fn dep -> elem(dep, 0) == :plug_crypto end) do
      Mix.raise("""
      :flick requires the :plug_crypto dependency. Add it to your mix.exs:

          {:plug_crypto, "~> 1.2 or ~> 2.0"}

      Then run `mix deps.get` and retry, or pass --no-plug-crypto to skip
      this check and decode with :erlang.binary_to_term/2 alone using `:safe`
      option.
      """)
    end
  end

  defp read_priv_file!(name) do
    path = Application.app_dir(:flick, "priv/#{name}")

    case File.read(path) do
      {:ok, source} -> source
      {:error, reason} -> Mix.raise("Failed to read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp write_file!(path, contents) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, contents)
    Mix.shell().info("* wrote #{path}")
  end

  defp web_lib_path(app_name, filename) do
    Path.join(["lib", "#{app_name}_web", filename])
  end

  defp module_to_filename(module_suffix) do
    module_suffix
    |> Macro.underscore()
    |> Kernel.<>(".ex")
  end

  defp default_layout_path(app_name) do
    Path.join(["lib", "#{app_name}_web", "components", "layouts", "root.html.heex"])
  end

  defp generate_socket_content(web_module, mod_suffix) do
    """
    defmodule #{web_module}.#{mod_suffix} do
      @moduledoc \"\"\"
      Raw WebSocket handler streaming ETF binary frames, decoded client-side
      with flick.js.
      \"\"\"
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
    """
  end

  defp generate_controller_content(web_module, mod_suffix, ctrl_suffix) do
    """
    defmodule #{web_module}.#{ctrl_suffix} do
      use #{web_module}, :controller

      def connect(conn, params) do
        WebSockAdapter.upgrade(conn, #{web_module}.#{mod_suffix}, params, [])
      end
    end
    """
  end
end
