defmodule Flick.Test.EtfEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :flick

  socket "/socket", Flick.Test.EtfSocket,
    websocket: [
      serializer: [{Flick.Socket.Serializer, "~> 2.0.0"}],
      check_origin: false
    ]
end
