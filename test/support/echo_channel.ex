defmodule Flick.Test.EchoChannel do
  @moduledoc false
  use Phoenix.Channel

  @impl true
  def join("room:lobby", _payload, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("echo", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end
end
