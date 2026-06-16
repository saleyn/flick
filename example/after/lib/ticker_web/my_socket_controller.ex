defmodule TickerWeb.MySocketController do
  use TickerWeb, :controller

  def connect(conn, params) do
    WebSockAdapter.upgrade(conn, TickerWeb.MySocket, params, [])
  end
end
