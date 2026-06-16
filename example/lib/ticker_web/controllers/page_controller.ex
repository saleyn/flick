defmodule TickerWeb.PageController do
  use TickerWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
