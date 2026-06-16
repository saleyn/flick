defmodule Flick.Test.EchoRouter do
  @moduledoc false
  use Plug.Router

  plug :match
  plug :dispatch

  get "/ws" do
    test_pid = :persistent_term.get({__MODULE__, :test_pid})

    WebSockAdapter.upgrade(conn, Flick.Test.EchoSocket, %{test_pid: test_pid}, [])
  end
end
