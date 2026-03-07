defmodule OrTools.NIF do
  @moduledoc false

  @on_load :load_nifs

  def load_nifs do
    path = :filename.join(:code.priv_dir(:or_tools), ~c"cp_sat")
    :erlang.load_nif(path, 0)
  end

  def solve(_vars, _constraints, _objective, _params), do: :erlang.nif_error(:nif_not_loaded)

  def solve_all(_vars, _constraints, _objective, _callback_pid, _ctrl, _params),
    do: :erlang.nif_error(:nif_not_loaded)

  def new_solve_ctrl(), do: :erlang.nif_error(:nif_not_loaded)

  def signal_solve(_ctrl, _reply), do: :erlang.nif_error(:nif_not_loaded)
end
