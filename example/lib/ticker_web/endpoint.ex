defmodule TickerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ticker

  plug Plug.Static,
    at: "/",
    from: :ticker,
    gzip: true,
    only: ~w(assets fonts images favicon.ico robots.txt)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, store: :cookie, key: "_ticker_key", signing_salt: "changeme"

  plug TickerWeb.Router
end
