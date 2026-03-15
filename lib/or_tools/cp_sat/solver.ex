defmodule OrTools.CpSat.Solver do
  @moduledoc false

  alias OrTools.CpSat
  alias OrTools.CpSat.Constraint
  alias OrTools.CpSat.Variable

  def solve(%CpSat{} = model, opts \\ []) do
    case CpSat.validate(model) do
      :ok ->
        params = Keyword.get(opts, :params, [])
        vars_tuples = Enum.map(model.vars, &Variable.to_tuple/1)

        constraints_tuples =
          Enum.map(model.interval_vars, &Variable.to_tuple/1) ++
            Enum.map(model.constraints, &Constraint.to_tuple/1)

        {status, values, objective} =
          OrTools.NIF.solve(vars_tuples, constraints_tuples, model.objective, params)

        {:ok, %{status: status, values: filter_internal(values), objective: objective}}

      {:error, _} = error ->
        error
    end
  end

  def solve!(%CpSat{} = model, opts \\ []) do
    case solve(model, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  def solve_all(%CpSat{} = model, opts \\ []) do
    on_solution = Keyword.get(opts, :on_solution)
    init = Keyword.get(opts, :init, fn variables -> variables end)
    params = Keyword.get(opts, :params, [])

    handler_opts =
      if on_solution do
        var_names =
          model.vars
          |> Enum.map(fn %Variable{name: name} -> name end)
          |> Enum.reject(&internal?/1)

        {init.(var_names), on_solution}
      end

    do_solve_all(model, handler_opts, params)
  end

  def solve_all!(%CpSat{} = model, opts \\ []) do
    case solve_all(model, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp do_solve_all(model, handler_opts, params) do
    case CpSat.validate(model) do
      :ok ->
        {callback_pid, ctrl} =
          if handler_opts do
            {init_state, on_solution} = handler_opts
            ctrl = OrTools.NIF.new_solve_ctrl()
            pid = spawn_solution_handler(model, init_state, on_solution, ctrl)
            {pid, ctrl}
          else
            {nil, nil}
          end

        vars_tuples = Enum.map(model.vars, &Variable.to_tuple/1)

        constraints_tuples =
          Enum.map(model.interval_vars, &Variable.to_tuple/1) ++
            Enum.map(model.constraints, &Constraint.to_tuple/1)

        {status, raw_solutions, metrics} =
          OrTools.NIF.solve_all(
            vars_tuples,
            constraints_tuples,
            model.objective,
            callback_pid,
            ctrl,
            params
          )

        final_state =
          if callback_pid do
            send(callback_pid, {:done, self()})

            receive do
              {:handler_done, state} -> state
            end
          end

        solutions =
          if callback_pid do
            nil
          else
            Enum.map(raw_solutions, fn {values, objective} ->
              %{values: filter_internal(values), objective: objective}
            end)
          end

        result = %{status: status, solutions: solutions, metrics: metrics}

        result =
          if final_state != nil do
            Map.put(result, :state, final_state)
          else
            result
          end

        {:ok, result}

      {:error, _} = error ->
        error
    end
  end

  defp internal?(name) when is_atom(name) do
    s = Atom.to_string(name)

    String.starts_with?(s, "__abs_") or
      String.starts_with?(s, "__mul_") or
      String.starts_with?(s, "__div_") or
      String.starts_with?(s, "__min_") or
      String.starts_with?(s, "__max_")
  end

  defp internal_names(vars) when is_list(vars) do
    vars
    |> Enum.map(fn %Variable{name: name} -> name end)
    |> Enum.filter(&internal?/1)
    |> MapSet.new()
  end

  defp filter_internal(values) when is_map(values) do
    Map.reject(values, fn {name, _} -> internal?(name) end)
  end

  defp reject_internal(values, internal_names) when is_map(values) do
    Map.reject(values, fn {name, _} -> MapSet.member?(internal_names, name) end)
  end

  defp spawn_solution_handler(model, init_state, callback, ctrl) do
    internal_names = internal_names(model.vars)

    spawn(fn ->
      solution_handler_loop(callback, internal_names, init_state, ctrl)
    end)
  end

  defp solution_handler_loop(callback, internal_names, state, ctrl) do
    receive do
      {:solution, _index, values, objective} ->
        solution = %{
          values: reject_internal(values, internal_names),
          objective: objective
        }

        case callback.(solution, state) do
          {:halt, new_state} ->
            OrTools.NIF.signal_solve(ctrl, :halt)

            receive do
              {:done, caller} -> send(caller, {:handler_done, new_state})
            end

          new_state ->
            OrTools.NIF.signal_solve(ctrl, :continue)
            solution_handler_loop(callback, internal_names, new_state, ctrl)
        end

      {:done, caller} ->
        send(caller, {:handler_done, state})
    end
  end
end
