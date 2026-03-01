defmodule OrTools.NIF do
  @moduledoc """
  NIF module for OR-Tools integration using Fine.
  """

  @on_load :load_nifs

  def load_nifs do
    path = :filename.join(:code.priv_dir(:or_tools), ~c"or_tools")
    :erlang.load_nif(path, 0)
  end

  @doc """
  Adds two integers together.

  ## Examples

      iex> OrTools.NIF.add(2, 3)
      5

  """
  def add(_x, _y) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
