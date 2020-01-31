defmodule LigrettoWeb.GameChannel do
  use LigrettoWeb, :channel
  alias Ligretto.Games
  alias Ligretto.Games.{Card, Pile}

  def join("game:" <> game_id, params, socket) do
    socket =
      socket
      |> assign(:game_id, game_id)
      |> assign(:player_id, params["player_id"])

    {:ok, socket}
  end

  def handle_in("player_joined", params, socket) do
    player = Games.get_player(params["player_id"])
    broadcast_from!(socket, "player_joined", Map.from_struct(player))
    {:noreply, socket}
  end

  def handle_info(:after_join, socket) do
    broadcast_from(socket, "player_joined", %{player_id: socket.assigns.player_id})
    {:noreply, socket}
  end

  def handle_in("set_ready", _params, socket) do
    Games.set_player_ready(socket.assigns.player_id)
    hand = Games.get_hand(socket.assigns.player_id)
    broadcast(socket, "player_ready", %{player_id: socket.assigns.player_id})
    {:reply, {:ok, Map.from_struct(hand)}, socket}
  end

  def handle_in("start_round", _params, socket) do
    case Games.start_round(socket.assigns.game_id) do
      :ok ->
        broadcast(socket, "round_started", %{})
        {:noreply, socket}
      _ -> {:noreply, socket}
    end
  end

  def handle_in("new_pile", params, socket) do
    card = %Card{
      id: params["id"],
      value: params["value"],
      location: params["location"],
      player: params["player"],
      color: params["color"]
    }
    pile = Games.create_new_pile(socket.assigns.game_id, card)
    broadcast(socket, "new_pile_created", pile) 
    {:reply, :ok, socket}
  end

  def handle_in("play_card", %{"pile_id" => pile_id, "card" => card}, socket) do
    card = %Card{
      id: card["id"],
      value: card["value"],
      location: card["location"],
      player: card["player"],
      color: card["color"]
    }
    case Games.play_card_on_pile(pile_id, card) do
      {:ok, updated_pile} ->
        broadcast(socket, "update_pile", updated_pile)
        {:reply, :ok, socket}
      {:error, message} ->
        {:reply, :error, socket}
    end
  end

  def handle_in("play_card", %{"card" => %Card{}, "pile_id" => pile_id}, socket) do
    {:reply, :ok, socket}
  end

  def handle_in("ligretto", _params, socket) do
    winning_player = Games.get_player(socket.assigns.player_id)
    players = Games.get_all_players(socket.assigns.game_id)
    {:ok, game} = Games.get_game(socket.assigns.game_id)

    results = Enum.map(players, fn p -> %{
      player_id: p.id,
      old_score: p.score,
      round_score: (p.stack * -2) + p.cards_played,
      new_score: p.score + (p.stack * -2) + p.cards_played,
      winner: p.id == winning_player.id
    } end)

    Games.set_all_player_scores(socket.assigns.game_id)
    Redix.command(:redix, ["HSET", socket.assigns.game_id, "state", "waiting_for_players"])
    Games.clear_all_piles(socket.assigns.game_id)

    case game.current_round == game.total_rounds do
      true ->
        broadcast(socket, "game_over", %{"results" => results})
      false ->
        broadcast(socket, "end_of_round", %{"results" => results})
    end
    
    {:noreply, socket}
  end

  def handle_in("moved_from_stack", _params, socket) do
    Games.subtract_player_stack(socket.assigns.player_id)
    {:noreply, socket}
  end
end