defmodule Ligretto.Games.Player do
  @derive [Poison.Encoder]
  defstruct [:id, :name, :color, :cards_played, :score, :leader, :ready, :stack]

  def new_player(name, color) do
    %Ligretto.Games.Player{
      id: nil,
      name: name,
      color: color,
      score: 0,
      leader: false,
      ready: false,
      stack: 10,
      cards_played: 0
    }
  end

  def player_round_score(%Ligretto.Games.Player{} = player) do
    (player.stack * -2) + player.cards_played
  end
end