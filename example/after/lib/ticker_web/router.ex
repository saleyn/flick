defmodule TickerWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", TickerWeb do
    pipe_through :browser

    # Added by mix flick.install:
    get "/ws", MySocketController, :connect

    get "/", PageController, :index
  end
end
