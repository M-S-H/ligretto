defmodule Ligretto.Games.Pile do
  @derive [Poison.Encoder]
  @derive Jason.Encoder
  defstruct [:id, :color, :currentValue, :cards]
end