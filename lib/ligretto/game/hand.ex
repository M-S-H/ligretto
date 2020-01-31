defmodule Ligretto.Games.Hand do
  @derive Jason.Encoder
  defstruct [:stack, :row, :hand, :location]

  def construct_hand(card_list) do
    shuffled_cards = Enum.shuffle(card_list)

    hand = %Ligretto.Games.Hand{
      stack: Enum.slice(shuffled_cards, 0, 10) |> Enum.map(fn c -> %{c | location: "stack"} end),
      row: Enum.slice(shuffled_cards, 10, 3) |> Enum.map(fn c -> %{c | location: "row"} end),
      hand: Enum.slice(shuffled_cards, 13, 27) |> Enum.map(fn c -> %{c | location: "hand"} end)
    }

    if (Enum.sum(Enum.map([Enum.at(hand.stack, 0) | hand.row], fn c -> c.value end))) < 30 do
      hand
    else
      construct_hand(card_list)
    end
  end
end