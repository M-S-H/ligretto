defmodule LigrettoWeb.GameController do
  use LigrettoWeb, :controller
  require Logger

  alias Ligretto.Games
  alias Ligretto.Games.{Card, Hand, Player, Game, Pile}


  def new_game(conn, %{"name" => name, "color" => color, "total_rounds" => total_rounds}) do
    case Games.create_game(total_rounds) do
      {:ok, game} ->
        {:ok, player} = Games.add_player_to_game(game.id, name, color, true)

        conn |>
        send_resp(200, Poison.encode!(%{game: game, player: player}))
      _ ->
        {:bad}
    end
  end

  def show(conn, %{"id" => game_id}) do
    case Games.get_game(game_id) do
      {:ok, game} ->
        players = Games.get_all_players(game_id)
        piles = Games.get_all_piles(game_id)
        conn
        |> send_resp(200, Poison.encode!(%{game: game, players: players, piles: piles}))
      _ ->
        conn
        |> send_resp(404, "Game not found")
    end
  end

  def join_game(conn, params) do
    case Games.add_player_to_game(params["game_id"], params["name"], params["color"]) do
      {:ok, player} ->
        {:ok, game} = Games.get_game(params["game_id"])
        conn
        |> send_resp(200, Poison.encode!(%{game: game, player: player}))
      _ ->
        conn
        |> send_resp(404, "Game not found")  
    end
  end

  def options do
  end

  def test(conn, _params) do
    conn
    |> send_resp(200, Mix.env |> to_string)
  end
end