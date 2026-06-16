defmodule Flick.Test.EtfSocket do
  @moduledoc false
  use Phoenix.Socket

  channel "room:*", Flick.Test.EchoChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
