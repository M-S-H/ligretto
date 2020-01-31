defmodule LigrettoWeb.Router do
  use LigrettoWeb, :router

  pipeline :api do
    plug CORSPlug, origin: "*"
    plug :accepts, ["json"]
  end

  scope "/api", LigrettoWeb do
    pipe_through :api

    get "/game/:id", GameController, :show
    post "/newgame", GameController, :new_game
    put "/joingame", GameController, :join_game
    get "/test", GameController, :test
    get "/clean", GameController, :clean

    options "/game/:id", GameController, :options
    options "/joingame", GameController, :options
    options "/newgame", GameController, :options
  end
end
