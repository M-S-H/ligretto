defmodule Ligretto.Games.Card do
  @derive [Poison.Encoder]
  @derive Jason.Encoder
  defstruct [:id, :value, :color, :player, :location]
end