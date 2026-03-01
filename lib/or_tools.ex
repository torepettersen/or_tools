defmodule OrTools do
  @moduledoc """
  Elixir interface to Google OR-Tools using Fine NIFs.
  """

  alias OrTools.NIF

  @doc """
  Adds two integers together using the NIF implementation.

  ## Examples

      iex> OrTools.add(2, 3)
      5

  """
  defdelegate add(x, y), to: NIF
end
