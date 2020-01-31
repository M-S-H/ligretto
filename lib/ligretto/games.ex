defmodule Ligretto.Games do
  @moduledoc """
  The Ligretto game context.
  """

  alias Ligretto.Games.Game
  alias Ligretto.Games.Player
  alias Ligretto.Games.Card
  alias Ligretto.Games.Pile
  alias Ligretto.Games.Hand

  @gameExp "14000"

  def create_game(total_rounds) do
    # Create game struct
    game = %Game{
      id: generate_game_id(),
      state: "gathering_players",
      current_round: 0,
      total_rounds: total_rounds,
    }

    # Save to Redis
    case set_game(game) do
      {:ok, _status} ->
        {:ok, game}
      {:error, reason} ->
        {:error, reason}
    end
  end


  def get_game(game_id) do
    case Redix.command(:redix, ["HGETALL", game_id]) do
      {:ok, []} -> {:error, :not_found}
      {:ok, data} ->
        game = %Game{
          id: game_id,
          state: Enum.at(data, 1),
          current_round: String.to_integer(Enum.at(data, 3)),
          total_rounds: String.to_integer(Enum.at(data, 5))
        }
        {:ok, game}
      {:error, reason} -> {:error, reason}
    end
  end


  def get_hand(player_id) do
    Enum.reduce(["red", "green", "blue", "yellow"], [], fn(color, list) -> list ++ Enum.reduce(1..10, [], fn(value, l) -> [%Card{id: generate_game_id(), value: value, color: color, player: player_id} | l] end) end)
    |> List.flatten
    |> Hand.construct_hand
  end


  def get_game_state(game_id) do
    case Redix.command(:redix, ["HGET", game_id, "state"]) do
      {:ok, state} ->
        state
      {:error, reason} ->
        :error
    end
  end

  def get_game_round(game_id) do
    case Redix.command(:redix, ["HGET", game_id, "current_round"]) do
      {:ok, round} -> Integer.parse(round)
      _ -> {:error, :bad}
    end
  end

  def start_round(game_id) do
    case get_game(game_id) do
      {:ok, game} ->
        game = %{game | state: "in_progress"}
        game = %{game | current_round: game.current_round + 1}
        set_game(game)
        reset_all_players_for_round(game.id)
        :ok
      _ -> :error
    end
  end

  
  def create_new_pile(game_id, %Card{} = card) do
    if card.value == 1 do
      case Redix.command(:redix, ["HGET", game_id, "state"]) do
        {:ok, x} when x == "in_progress" ->
          pile_list_id = game_id <> ":piles"
          pile = %Pile{id: generate_tagged_id(game_id), currentValue: 1, cards: [card], color: card.color}
          serialized = Poison.encode!(pile)
          Redix.command(:redix, ["SET", pile.id, serialized])
          Redix.command(:redix, ["LPUSH", pile_list_id, pile.id])
          
          if (card.location == "stack") do
            subtract_player_stack(card.player)
          end
          increment_cards_played(card.player)

          pile
        {:ok, x} when x != nil ->
          {:error, :game_not_in_progress}
        {:ok, nil} ->
          {:error, :game_does_not_exist}
      end
    else
      {:error, :invalid_value} 
    end
  end

  def get_all_piles(game_id) do
    pile_list_id = game_id <> ":piles"
    {:ok, pile_ids} = Redix.command(:redix, ["LRANGE", pile_list_id, 0, -1])
    Enum.map(pile_ids, fn pid -> get_pile(pid) end)
  end

  def get_pile(pile_id) do
    case Redix.command(:redix, ["GET", pile_id]) do
      {:ok, x} when x != nil ->
        Poison.decode!(x, as: %Pile{cards: [%Card{}]})
      {:ok, _} ->
        {:error, :pile_does_not_exist}
    end
  end

  def play_card_on_pile(pile_id, %Card{} = card) do
    resource = pile_id <> ":LOCK"
    case Redlock.lock(resource, 60) do
      {:ok, mutex} ->
        pile = get_pile(pile_id)
        cond do
          pile.color != card.color ->
            Redlock.unlock(resource, mutex)
            {:error, :wrong_color}
          card.value != pile.currentValue + 1 ->
            Redlock.unlock(resource, mutex)
            {:error, :wrong_value}
          true ->
            if (card.location == "stack") do
              subtract_player_stack(card.player)
            end
            increment_cards_played(card.player)
            updated_pile = %{pile | currentValue: card.value, cards: pile.cards ++ [card]}
            serialized = Poison.encode!(updated_pile)
            Redix.command(:redix, ["SET", pile_id, serialized])
            Redlock.unlock(resource, mutex)
            {:ok, updated_pile}
        end
      :error ->
        {:error, :system_error}
    end
  end


  def add_player_to_game(game_id, name, color, leader \\ false) do
    player_list_id = game_id <> ":players"
    player_id = "P:" <> generate_tagged_id(game_id)
    player = %{ Player.new_player(name, color) | id: player_id, leader: leader }
    Redix.command(:redix, ["LPUSH", player_list_id, player.id])
    Redix.command(:redix, ["HSET", player.id, "id", player.id, "name", player.name, "color", player.color, "leader", player.leader, "ready", player.ready, "score", player.score, "cards_played", player.cards_played, "stack", player.stack])
    {:ok, player}
  end

  def clear_all_piles(game_id) do
    piles = get_all_piles(game_id)
    Enum.map(piles, fn p -> Redix.command(:redix, ["DEL", p.id]) end)
    Redix.command(:redix, ["DEL", game_id <> ":piles"])
  end


  def set_player_score(player_id, score) do
    case Redix.command(:redix, ["HSET", player_id, "score", score]) do
      {:ok, _} -> {:ok, score}
      {:error, reason} -> {:error, reason}
    end
  end

  def reset_player_for_round(player_id) do
    case Redix.command(:redix, ["HSET", player_id, "stack", 10, "cards_played", 0, "ready", false]) do
      {:ok, _} -> {:ok, :done}
      {:error, reason} -> {:error, reason}
    end
  end

  def reset_all_players_for_round(game_id) do
    player_list_id = game_id <> ":players"
    {:ok, player_ids} = Redix.command(:redix, ["LRANGE", player_list_id, 0, -1])
    Enum.map(player_ids, fn pid -> reset_player_for_round(pid) end)
    :oks
  end

  def set_all_player_scores(game_id) do
    players = get_all_players(game_id)
    players
    |> Enum.map(fn p -> Redix.command(:redix, ["HSET", p.id, "score", Player.player_round_score(p) + p.score]) end)
  end

  def subtract_player_stack(player_id) do
    {:ok, stack} = Redix.command(:redix, ["HGET", player_id, "stack"])
    Redix.command(:redix, ["HSET", player_id, "stack", String.to_integer(stack) - 1])
  end

  def increment_cards_played(player_id) do
    {:ok, stack} = Redix.command(:redix, ["HGET", player_id, "cards_played"])
    Redix.command(:redix, ["HSET", player_id, "cards_played", String.to_integer(stack) + 1])
  end

  def is_player_ready?(player_id) do
    case Redix.command(:redix, ["HGET", player_id, "ready"]) do
      {:ok, state} when state != nil ->
        state
      {:ok, nil} -> {:error, :player_does_not_exist}
      {:error, reason} -> {:error, reason}
    end
  end

  def set_player_ready(player_id) do
    Redix.command(:redix, ["HSET", player_id, "ready", "true"])
    :ok
  end

  def get_player(player_id) do
    case Redix.command(:redix, ["HGETALL", player_id]) do
      {:ok, player} ->
        %Player{
          id: Enum.at(player, 1),
          name: Enum.at(player, 3),
          color: Enum.at(player, 5),
          leader: Enum.at(player, 7) == "true",
          ready: Enum.at(player, 9) == "true",
          score: String.to_integer(Enum.at(player, 11)),
          cards_played: String.to_integer(Enum.at(player, 13)),
          stack: String.to_integer(Enum.at(player, 15))
        }
      _ -> {:error}
    end
  end

  def get_all_players(game_id) do
    player_list_id = game_id <> ":players"
    {:ok, player_ids} = Redix.command(:redix, ["LRANGE", player_list_id, 0, -1])
    Enum.map(player_ids, fn pid -> get_player(pid) end)
  end

  def all_players_ready?(game_id) do
    player_list_id = game_id <> ":players"
    {:ok, player_ids} = Redix.command(:redix, ["LRANGE", player_list_id, 0, -1])
    player_states = Enum.map(player_ids, fn x -> is_player_ready?(x) end)
    Enum.all?(player_states, fn x -> x == "true" end)
  end

  defp set_game(%Game{} = game) do
    case Redix.command(:redix, ["HSET", game.id, "state", game.state, "current_round", game.current_round, "total_rounds", game.total_rounds]) do
      {:ok, _status} ->
        {:ok, game}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_game_id do
    Ecto.UUID.generate()
    |> String.slice(0..4)
    |> String.upcase
  end

  defp generate_tagged_id(game_id) do
    id = Ecto.UUID.generate()
    |> String.slice(0..4)
    id <> ":" <> game_id
  end

  def test_action(value) do
    t = DateTime.utc_now
    target = t.minute + 1
    test_action(value, target)
  end


  def test_action(value, target) do
    t = DateTime.utc_now
    cond do
      t.minute == target ->
        p = %Player{
          id: generate_game_id(),
          name: generate_game_id()
        }
        # add_player_to_game("018E4", p)
      t.minute < target ->
        :timer.sleep(10)
        test_action(value, target)
    end
  end
end