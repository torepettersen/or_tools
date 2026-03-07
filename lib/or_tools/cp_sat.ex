defmodule OrTools.CpSat do
  @moduledoc """
  Immutable CP-SAT constraint programming model.

  ## Example

      use OrTools.CpSat

      model =
        CpSat.new()
        |> CpSat.int_var(:x, 0..50)
        |> CpSat.int_var(:y, 0..50)
        |> CpSat.int_var(:z, 0..50)
        |> CpSat.constrain(2 * :x + 7 * :y + 3 * :z <= 50)
        |> CpSat.constrain(3 * :x - 5 * :y + 7 * :z <= 45)
        |> CpSat.constrain(5 * :x + 2 * :y - 6 * :z <= 37)
        |> CpSat.maximize(2 * :x + 2 * :y + 3 * :z)

      result = CpSat.solve!(model)
      result.status    # :optimal
      result.values    # %{x: 7, y: 3, z: 5}
      result.objective # 35.0
  """

  alias OrTools.CpSat.Constraint
  alias OrTools.CpSat.Expr
  alias OrTools.CpSat.Variable

  defmacro __using__(_opts) do
    quote do
      alias OrTools.CpSat
      require OrTools.CpSat
    end
  end

  defstruct vars: [], constraints: [], objective: nil

  @type linear_expr :: [{atom(), integer()}]
  @type op :: :<= | :>= | :== | :!= | :< | :>

  @doc "Creates a new empty model."
  def new, do: %__MODULE__{}

  @doc "Creates a boolean (0/1) variable with the given name."
  def bool_var(name) when is_atom(name) do
    %Variable{type: :bool, name: name}
  end

  def bool_var(%__MODULE__{} = model, name) when is_atom(name) do
    Map.update!(model, :vars, &(&1 ++ [bool_var(name)]))
  end

  @doc "Adds boolean (0/1) variables for each name in the list."
  def bool_vars(%__MODULE__{} = model, names) when is_list(names) do
    new_vars = Enum.map(names, &bool_var/1)
    Map.update!(model, :vars, &(&1 ++ new_vars))
  end

  @doc "Creates an integer variable with the given name and range."
  def int_var(name, %Range{first: lower_bound, last: upper_bound}) when is_atom(name) do
    int_var(name, lower_bound, upper_bound)
  end

  def int_var(name, lower_bound, upper_bound) when is_atom(name) and is_integer(lower_bound) and is_integer(upper_bound) do
    %Variable{type: :int, name: name, lower_bound: lower_bound, upper_bound: upper_bound}
  end

  @doc "Adds an integer variable to a model."
  def int_var(%__MODULE__{} = model, name, %Range{} = range) when is_atom(name) do
    Map.update!(model, :vars, &(&1 ++ [int_var(name, range)]))
  end

  def int_var(%__MODULE__{} = model, name, lower_bound, upper_bound) when is_atom(name) do
    Map.update!(model, :vars, &(&1 ++ [int_var(name, lower_bound, upper_bound)]))
  end

  @doc "Adds integer variables with the given range for each name in the list."
  def int_vars(%__MODULE__{} = model, names, %Range{} = range) when is_list(names) do
    new_vars = Enum.map(names, &int_var(&1, range))
    Map.update!(model, :vars, &(&1 ++ new_vars))
  end

  @doc """
  Builds a constraint without adding it to a model.

  Returns a `Constraint` struct that can be collected into a model:

      for shift <- shifts, into: model do
        assignments = Enum.map(employees, fn emp -> var_name(emp, shift) end)
        CpSat.constrain(sum(assignments) <= 1)
      end
  """
  defmacro constrain(expr) do
    {lhs_ast, op, rhs_ast} = parse_constraint_ast(expr)

    quote do
      {terms, op, rhs} =
        OrTools.CpSat.__build_constraint__(unquote(lhs_ast), unquote(rhs_ast), unquote(op))

      %OrTools.CpSat.Constraint{type: :linear, data: {terms, op, rhs}}
    end
  end

  @doc """
  Adds a linear constraint. Does not validate variable names.

  ## Examples

      CpSat.constrain(model, 2 * :x + 7 * :y <= 50)
  """
  defmacro constrain(model, expr) do
    {lhs_ast, op, rhs_ast} = parse_constraint_ast(expr)

    quote do
      {terms, op, rhs} =
        OrTools.CpSat.__build_constraint__(unquote(lhs_ast), unquote(rhs_ast), unquote(op))

      OrTools.CpSat.add_constraint(unquote(model), terms, op, rhs)
    end
  end

  @doc false
  def add_constraint(%__MODULE__{} = model, terms, op, rhs) do
    Map.update!(model, :constraints, &(&1 ++ [%Constraint{type: :linear, data: {terms, op, rhs}}]))
  end

  @doc """
  Creates an all-different constraint. Does not validate variable names.

  Each item can be a variable name (atom) or an `Expr` (single variable with
  a constant offset). Useful for diagonal constraints:

      CpSat.all_different(Enum.map(board_range, fn i -> CpSat.expr(:"q\#{i}" + i) end))

  Returns a `Constraint` struct that can be collected into a model.
  """
  def all_different(items) when is_list(items) do
    name_offsets = expand_all_different_items(items)
    %Constraint{type: :all_different, data: name_offsets}
  end

  @doc "Adds an all-different constraint to a model."
  def all_different(%__MODULE__{} = model, items) when is_list(items) do
    Map.update!(model, :constraints, &(&1 ++ [all_different(items)]))
  end

  defp expand_all_different_items(items) do
    Enum.map(items, fn
      name when is_atom(name) -> {name, 0}
      %Expr{terms: [{name, 1}], const: offset, special: []} -> {name, offset}
    end)
  end

  @doc "Constrains exactly one of the given boolean variables to be true."
  def exactly_one(var_names) when is_list(var_names) do
    %Constraint{type: :exactly_one, data: var_names}
  end

  def exactly_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    Map.update!(model, :constraints, &(&1 ++ [exactly_one(var_names)]))
  end

  @doc "Constrains at most one of the given boolean variables to be true."
  def at_most_one(var_names) when is_list(var_names) do
    %Constraint{type: :at_most_one, data: var_names}
  end

  def at_most_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    Map.update!(model, :constraints, &(&1 ++ [at_most_one(var_names)]))
  end

  @doc "Constrains at least one of the given boolean variables to be true."
  def at_least_one(var_names) when is_list(var_names) do
    %Constraint{type: :at_least_one, data: var_names}
  end

  def at_least_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    Map.update!(model, :constraints, &(&1 ++ [at_least_one(var_names)]))
  end

  @doc "Constrains the boolean AND of the given variables to be true."
  def bool_and(var_names) when is_list(var_names) do
    %Constraint{type: :bool_and, data: var_names}
  end

  def bool_and(%__MODULE__{} = model, var_names) when is_list(var_names) do
    Map.update!(model, :constraints, &(&1 ++ [bool_and(var_names)]))
  end

  @doc "Constrains the boolean OR of the given variables to be true."
  def bool_or(var_names) when is_list(var_names) do
    %Constraint{type: :bool_or, data: var_names}
  end

  def bool_or(%__MODULE__{} = model, var_names) when is_list(var_names) do
    Map.update!(model, :constraints, &(&1 ++ [bool_or(var_names)]))
  end

  @doc "Constrains the boolean XOR of the given variables to be true."
  def bool_xor(var_names) when is_list(var_names) do
    %Constraint{type: :bool_xor, data: var_names}
  end

  def bool_xor(%__MODULE__{} = model, var_names) when is_list(var_names) do
    Map.update!(model, :constraints, &(&1 ++ [bool_xor(var_names)]))
  end

  @doc """
  Builds an `%Expr{}` from a mathematical expression.

  ## Examples

      iex> CpSat.expr(2 * :x + 3 * :y)
      #Expr<2*x + 3*y>

      iex> CpSat.expr(-pow(:x + :y - 10, 2))
      #Expr<-pow(..., 2)>
  """
  defmacro expr(expression) do
    quote_collect_terms(expression)
  end

  @doc """
  Returns a zero expression. Use with `into:` to collect expressions:

      for emp <- employees, into: CpSat.expr() do
        score(model, emp)
      end
  """
  def expr, do: %Expr{}

  @doc "Sets the objective to maximize. Does not validate variable names."
  defmacro maximize(model, expr) do
    terms_ast = quote_collect_terms(expr)

    quote do
      OrTools.CpSat.__build_objective__(unquote(model), :maximize, unquote(terms_ast))
    end
  end

  @doc "Sets the objective to minimize. Does not validate variable names."
  defmacro minimize(model, expr) do
    terms_ast = quote_collect_terms(expr)

    quote do
      OrTools.CpSat.__build_objective__(unquote(model), :minimize, unquote(terms_ast))
    end
  end

  @doc false
  def set_objective(%__MODULE__{} = model, sense, terms) do
    Map.put(model, :objective, {sense, terms})
  end

  @doc false
  def __build_objective__(%__MODULE__{} = model, sense, %Expr{} = expr) do
    {model, linear_terms} = flatten_expr(model, expr)
    vars = merge_terms(linear_terms)
    set_objective(model, sense, vars)
  end

  # Linearizes an %Expr{} into {model, [{atom, int}]} by converting special terms
  # into auxiliary variables and constraints.
  defp flatten_expr(model, %Expr{terms: terms, const: _const, special: special}) do
    var_bounds = Map.new(model.vars, fn %Variable{name: name, lower_bound: lower_bound, upper_bound: upper_bound} ->
      {name, {lower_bound || 0, upper_bound || 1}}
    end)

    Enum.reduce(special, {model, terms}, fn
      {:abs, %Expr{} = inner, coeff}, {model, acc} ->
        abs_name = :"__abs_#{:erlang.unique_integer([:positive])}"

        max_bound =
          Enum.sum_by(inner.terms, fn {name, c} ->
            {lower_bound, upper_bound} = Map.get(var_bounds, name, {0, 0})
            max(abs(lower_bound * c), abs(upper_bound * c))
          end) + abs(inner.const)

        model = int_var(model, abs_name, 0, max_bound)

        model = Map.update!(model, :constraints, &(&1 ++ [%Constraint{type: :abs_eq, data: {abs_name, inner.terms, inner.const}}]))

        {model, [{abs_name, coeff} | acc]}

      {:pow, %Expr{} = base, exponent, coeff}, {model, acc} ->
        # If the base is a single variable with coeff 1 and no constant, reuse it directly.
        {model, var_bounds, source_var} =
          case {base.terms, base.const} do
            {[{base_var, 1}], 0} ->
              {model, var_bounds, base_var}

            _ ->
              aux_name = :"__pow_base_#{:erlang.unique_integer([:positive])}"

              all_extremes =
                Enum.reduce(base.terms, [{base.const, base.const}], fn {name, c}, ranges ->
                  {lower_bound, upper_bound} = Map.get(var_bounds, name, {0, 0})

                  for {lo, hi} <- ranges, v <- [lower_bound * c, upper_bound * c] do
                    {min(lo + v, lo), max(hi + v, hi)}
                  end
                end)

              aux_lower_bound = all_extremes |> Enum.map(&elem(&1, 0)) |> Enum.min()
              aux_upper_bound = all_extremes |> Enum.map(&elem(&1, 1)) |> Enum.max()

              model = int_var(model, aux_name, aux_lower_bound, aux_upper_bound)
              var_bounds = Map.put(var_bounds, aux_name, {aux_lower_bound, aux_upper_bound})

              eq_terms = base.terms ++ [{aux_name, -1}]

              model = Map.update!(model, :constraints, &(&1 ++ [%Constraint{type: :linear, data: {eq_terms, :==, -base.const}}]))

              {model, var_bounds, aux_name}
          end

        # Chain: aux1 = source * source, aux2 = aux1 * source, ...
        {model, _var_bounds, result_var} =
          Enum.reduce(2..exponent, {model, var_bounds, source_var}, fn i, {model, variable_bounds, prev_var} ->
            pow_name = :"__pow_#{:erlang.unique_integer([:positive])}"

            {prev_lower, prev_upper} = Map.get(variable_bounds, prev_var, {0, 0})
            {src_lower, src_upper} = Map.get(variable_bounds, source_var, {0, 0})

            products = [prev_lower * src_lower, prev_lower * src_upper, prev_upper * src_lower, prev_upper * src_upper]
            pow_lower_bound = Enum.min(products)
            pow_upper_bound = Enum.max(products)

            model = int_var(model, pow_name, pow_lower_bound, pow_upper_bound)
            variable_bounds = Map.put(variable_bounds, pow_name, {pow_lower_bound, pow_upper_bound})

            factors =
              if i > 2 do
                [prev_var, source_var]
              else
                [source_var, source_var]
              end

            model = Map.update!(model, :constraints, &(&1 ++ [%Constraint{type: :mul_eq, data: {pow_name, factors}}]))

            {model, variable_bounds, pow_name}
          end)

        {model, [{result_var, coeff} | acc]}

      {:mul, %Expr{} = left, %Expr{} = right, coeff}, {model, acc} ->
        [{left_var, 1}] = left.terms
        [{right_var, 1}] = right.terms

        {left_lower, left_upper} = Map.get(var_bounds, left_var, {0, 0})
        {right_lower, right_upper} = Map.get(var_bounds, right_var, {0, 0})
        products = for l <- [left_lower, left_upper], r <- [right_lower, right_upper], do: l * r

        mul_name = :"__mul_#{:erlang.unique_integer([:positive])}"
        model = int_var(model, mul_name, Enum.min(products), Enum.max(products))

        model = Map.update!(model, :constraints, &(&1 ++ [%Constraint{type: :mul_eq, data: {mul_name, [left_var, right_var]}}]))

        {model, [{mul_name, coeff} | acc]}

      {:min, var_names, coeff}, {model, acc} ->
        bounds = Enum.map(var_names, fn name -> Map.get(var_bounds, name, {0, 0}) end)

        min_name = :"__min_#{:erlang.unique_integer([:positive])}"

        model =
          int_var(
            model,
            min_name,
            Enum.min_by(bounds, &elem(&1, 0)) |> elem(0),
            Enum.min_by(bounds, &elem(&1, 1)) |> elem(1)
          )

        model = Map.update!(model, :constraints, &(&1 ++ [%Constraint{type: :min_eq, data: {min_name, var_names}}]))

        {model, [{min_name, coeff} | acc]}

      {:max, var_names, coeff}, {model, acc} ->
        bounds = Enum.map(var_names, fn name -> Map.get(var_bounds, name, {0, 0}) end)

        max_name = :"__max_#{:erlang.unique_integer([:positive])}"

        model =
          int_var(
            model,
            max_name,
            Enum.max_by(bounds, &elem(&1, 0)) |> elem(0),
            Enum.max_by(bounds, &elem(&1, 1)) |> elem(1)
          )

        model = Map.update!(model, :constraints, &(&1 ++ [%Constraint{type: :max_eq, data: {max_name, var_names}}]))

        {model, [{max_name, coeff} | acc]}

      {:div, %Expr{} = dividend, %Expr{} = divisor, coeff}, {model, acc} ->
        [{dividend_var, 1}] = dividend.terms
        [{divisor_var, 1}] = divisor.terms

        {dividend_lower, dividend_upper} = Map.get(var_bounds, dividend_var, {0, 0})
        {divisor_lower, divisor_upper} = Map.get(var_bounds, divisor_var, {1, 1})

        quotients =
          for n <- [dividend_lower, dividend_upper], d <- [divisor_lower, divisor_upper], d != 0, do: Kernel.div(n, d)

        div_name = :"__div_#{:erlang.unique_integer([:positive])}"
        model = int_var(model, div_name, Enum.min(quotients), Enum.max(quotients))

        model = Map.update!(model, :constraints, &(&1 ++ [%Constraint{type: :div_eq, data: {div_name, dividend_var, divisor_var}}]))

        {model, [{div_name, coeff} | acc]}
    end)
  end

  @doc """
  Validates and solves the model. Returns `{:ok, result}` or `{:error, reason}`.

  Always validates variable names before calling the solver.

  ## Options

      CpSat.solve(model, params: [max_time_in_seconds: 10.0, num_workers: 4])

  Supported params: `max_time_in_seconds`, `max_number_of_conflicts`, `num_workers`,
  `random_seed`, `log_search_progress`.
  """
  def solve(%__MODULE__{} = model, opts \\ []) do
    case validate(model) do
      :ok ->
        params = Keyword.get(opts, :params, [])

        # Convert structs to tuples for NIF
        vars_tuples = Enum.map(model.vars, &Variable.to_tuple/1)
        constraints_tuples = Enum.map(model.constraints, &Constraint.to_tuple/1)

        {status, values, objective} =
          OrTools.NIF.solve(vars_tuples, constraints_tuples, model.objective, params)

        visible_values = filter_internal_values(values)

        {:ok, %{status: status, values: visible_values, objective: objective}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates and solves the model. Returns the result or raises on error.

  See `solve/2` for options.
  """
  def solve!(%__MODULE__{} = model, opts \\ []) do
    case solve(model, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Enumerates all solutions. Returns `{:ok, result}` or `{:error, reason}`.

  The result contains `:status`, `:solutions` (a list of value maps), and `:metrics`.

  ## Options

  **No options** — collects all solutions in memory:

      CpSat.solve_all(model)

  **`:on_solution`** — called with each solution and the current state as it
  is found. Solutions are not stored in memory, only counted. The final state
  is available as `result.state`.

  **`:init`** — called with the model's variable names to produce the initial
  state. Defaults to `fn variables -> variables end`.

      CpSat.solve_all(model,
        init: fn variables -> {variables, 0} end,
        on_solution: fn solution, {variables, count} ->
          variables
          |> Enum.map_join(" ", fn name -> "\#{name}=\#{solution.values[name]}" end)
          |> IO.puts()
          {variables, count + 1}
        end)
  """
  def solve_all(%__MODULE__{} = model, opts \\ []) do
    on_solution = Keyword.get(opts, :on_solution)
    init = Keyword.get(opts, :init, fn variables -> variables end)
    params = Keyword.get(opts, :params, [])

    handler_opts =
      if on_solution do
        var_names = model.vars |> Enum.map(fn %Variable{name: name} -> name end) |> Enum.reject(&internal_var?/1)
        {init.(var_names), on_solution}
      end

    do_solve_all(model, handler_opts, params)
  end

  defp do_solve_all(model, handler_opts, params) do
    case validate(model) do
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

        # Convert structs to tuples for NIF
        vars_tuples = Enum.map(model.vars, &Variable.to_tuple/1)
        constraints_tuples = Enum.map(model.constraints, &Constraint.to_tuple/1)

        {status, raw_solutions, metrics} =
          OrTools.NIF.solve_all(vars_tuples, constraints_tuples, model.objective, callback_pid, ctrl, params)

        final_state =
          if callback_pid do
            send(callback_pid, {:done, self()})

            receive do
              {:handler_done, state} -> state
            end
          end

        solutions =
          Enum.map(raw_solutions, fn {values, objective} ->
            %{values: filter_internal_values(values), objective: objective}
          end)

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

  @doc """
  Enumerates all solutions. Returns the result or raises on error.

  See `solve_all/2` for options.
  """
  def solve_all!(%__MODULE__{} = model, opts \\ []) do
    case solve_all(model, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp spawn_solution_handler(model, init_state, callback, ctrl) do
    internal_prefixes = internal_var_prefixes(model)

    spawn(fn ->
      solution_handler_loop(callback, internal_prefixes, init_state, ctrl)
    end)
  end

  defp solution_handler_loop(callback, internal_prefixes, state, ctrl) do
    receive do
      {:solution, _index, values, objective} ->
        solution = %{values: reject_internal(values, internal_prefixes), objective: objective}

        case callback.(solution, state) do
          {:halt, new_state} ->
            OrTools.NIF.signal_solve(ctrl, :halt)

            receive do
              {:done, caller} -> send(caller, {:handler_done, new_state})
            end

          new_state ->
            OrTools.NIF.signal_solve(ctrl, :continue)
            solution_handler_loop(callback, internal_prefixes, new_state, ctrl)
        end

      {:done, caller} ->
        send(caller, {:handler_done, state})
    end
  end

  defp internal_var_prefixes(model) do
    model.vars
    |> Enum.map(fn %Variable{name: name} -> name end)
    |> Enum.filter(&internal_var?/1)
    |> MapSet.new()
  end

  defp reject_internal(values, internal_names) do
    Map.reject(values, fn {name, _} -> MapSet.member?(internal_names, name) end)
  end

  defp internal_var?(name) do
    name_string = Atom.to_string(name)

    String.starts_with?(name_string, "__abs_") or String.starts_with?(name_string, "__pow_") or
      String.starts_with?(name_string, "__mul_") or String.starts_with?(name_string, "__div_") or
      String.starts_with?(name_string, "__min_") or String.starts_with?(name_string, "__max_")
  end

  defp filter_internal_values(values) do
    Map.reject(values, fn {name, _} -> internal_var?(name) end)
  end

  @doc """
  Validates the model without solving. Returns `:ok` or `{:error, reason}`.
  """
  def validate(%__MODULE__{} = model) do
    declared = declared_var_names(model)

    with :ok <- validate_constraints(model.constraints, declared),
         :ok <- validate_objective(model.objective, declared) do
      :ok
    end
  end

  # --- Validation helpers ---

  defp declared_var_names(%__MODULE__{vars: vars}) do
    MapSet.new(vars, fn %Variable{name: name} -> name end)
  end

  defp validate_constraints([], _declared), do: :ok

  defp validate_constraints([%Constraint{} = constraint | rest], declared) do
    case validate_constraint(constraint, declared) do
      :ok -> validate_constraints(rest, declared)
      error -> error
    end
  end

  defp validate_constraint(%Constraint{type: :all_different, data: name_offsets}, declared) do
    names = Enum.map(name_offsets, &elem(&1, 0))
    check_var_names(names, declared)
  end

  defp validate_constraint(%Constraint{type: type, data: var_names}, declared)
       when type in [
              :exactly_one,
              :at_most_one,
              :at_least_one,
              :bool_and,
              :bool_or,
              :bool_xor
            ] do
    check_var_names(var_names, declared)
  end

  defp validate_constraint(%Constraint{type: :abs_eq, data: {target, terms, _const}}, declared) do
    with :ok <- check_var_names([target], declared),
         :ok <- check_terms(terms, declared) do
      :ok
    end
  end

  defp validate_constraint(%Constraint{type: type, data: {target, var_names}}, declared)
       when type in [:mul_eq, :min_eq, :max_eq] do
    check_var_names([target | var_names], declared)
  end

  defp validate_constraint(%Constraint{type: :div_eq, data: {target, dividend, divisor}}, declared) do
    check_var_names([target, dividend, divisor], declared)
  end

  defp validate_constraint(%Constraint{type: :linear, data: {terms, _op, _rhs}}, declared) do
    check_terms(terms, declared)
  end

  defp validate_objective(nil, _declared), do: :ok

  defp validate_objective({_sense, terms}, declared) do
    check_terms(terms, declared)
  end

  defp check_terms(terms, declared) do
    terms
    |> Enum.map(&elem(&1, 0))
    |> check_var_names(declared)
  end

  defp check_var_names(names, declared) do
    unknown = Enum.reject(names, &MapSet.member?(declared, &1))

    case unknown do
      [] ->
        :ok

      unknown ->
        declared_list = declared |> MapSet.to_list() |> Enum.sort()

        {:error,
         "unknown variable(s) #{inspect(unknown)} in model. " <>
           "Declared variables: #{inspect(declared_list)}"}
    end
  end

  # --- Runtime helpers for expression normalization ---

  @doc false
  def __build_constraint__(%Expr{} = lhs, %Expr{} = rhs, op) do
    combined = Expr.subtract(lhs, rhs)

    if combined.special != [] do
      raise ArgumentError,
            "constraints cannot contain nonlinear terms (abs, pow, mul, div, min, max)"
    end

    final_vars = merge_terms(combined.terms)
    {final_vars, op, -combined.const}
  end

  defp merge_terms(terms) do
    terms
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {var, coeffs} -> {var, Enum.sum(coeffs)} end)
    |> Enum.reject(fn {_, coeff} -> coeff == 0 end)
  end

  # --- Macro helpers (compile-time AST → runtime %Expr{}) ---

  defp parse_constraint_ast({op, _, [lhs, rhs]}) when op in [:<=, :>=, :==, :!=, :<, :>] do
    {quote_collect_terms(lhs), op, quote_collect_terms(rhs)}
  end

  # Addition
  defp quote_collect_terms({:+, _, [left, right]}) do
    l = quote_collect_terms(left)
    r = quote_collect_terms(right)
    quote do: OrTools.CpSat.Expr.add(unquote(l), unquote(r))
  end

  # Subtraction
  defp quote_collect_terms({:-, _, [left, right]}) do
    l = quote_collect_terms(left)
    r = quote_collect_terms(right)
    quote do: OrTools.CpSat.Expr.subtract(unquote(l), unquote(r))
  end

  # Unary negation
  defp quote_collect_terms({:-, _, [operand]}) do
    o = quote_collect_terms(operand)
    quote do: OrTools.CpSat.Expr.negate(unquote(o))
  end

  # min(var_list) / max(var_list)
  defp quote_collect_terms({:min, _, [arg]}) do
    quote do: %OrTools.CpSat.Expr{special: [{:min, unquote(arg), 1}]}
  end

  defp quote_collect_terms({:max, _, [arg]}) do
    quote do: %OrTools.CpSat.Expr{special: [{:max, unquote(arg), 1}]}
  end

  # abs(expr)
  defp quote_collect_terms({:abs, _, [inner]}) do
    inner_ast = quote_collect_terms(inner)
    quote do: %OrTools.CpSat.Expr{special: [{:abs, unquote(inner_ast), 1}]}
  end

  # div(dividend, divisor)
  defp quote_collect_terms({:div, _, [dividend, divisor]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)

    quote do: %OrTools.CpSat.Expr{
            special: [{:div, unquote(dividend_ast), unquote(divisor_ast), 1}]
          }
  end

  # pow(expr, exponent)
  defp quote_collect_terms({:pow, _, [base, exp]}) when is_integer(exp) and exp >= 2 do
    base_ast = quote_collect_terms(base)
    quote do: %OrTools.CpSat.Expr{special: [{:pow, unquote(base_ast), unquote(exp), 1}]}
  end

  # sum(list) — reduces a runtime list into a single Expr
  defp quote_collect_terms({:sum, _, [arg]}) do
    quote do: OrTools.CpSat.Expr.sum(unquote(arg))
  end

  # coeff * special_expr or special_expr * coeff — delegate to Expr.scale
  # We handle all coeff * f(...) patterns uniformly via scale

  # coeff * sum(...)
  defp quote_collect_terms({:*, _, [coeff, {:sum, _, _} = sum_expr]}) do
    sum_ast = quote_collect_terms(sum_expr)
    coeff_ast = quote_collect_terms_coeff(coeff)
    quote do: OrTools.CpSat.Expr.scale(unquote(sum_ast), unquote(coeff_ast))
  end

  defp quote_collect_terms({:*, _, [{:sum, _, _} = sum_expr, coeff]}) do
    sum_ast = quote_collect_terms(sum_expr)
    coeff_ast = quote_collect_terms_coeff(coeff)
    quote do: OrTools.CpSat.Expr.scale(unquote(sum_ast), unquote(coeff_ast))
  end

  # coeff * min/max
  defp quote_collect_terms({:*, _, [coeff, {:min, _, [arg]}]}) do
    coeff_ast = quote_collect_terms_coeff(coeff)
    quote do: %OrTools.CpSat.Expr{special: [{:min, unquote(arg), unquote(coeff_ast)}]}
  end

  defp quote_collect_terms({:*, _, [{:min, _, [arg]}, coeff]}) do
    coeff_ast = quote_collect_terms_coeff(coeff)
    quote do: %OrTools.CpSat.Expr{special: [{:min, unquote(arg), unquote(coeff_ast)}]}
  end

  defp quote_collect_terms({:*, _, [coeff, {:max, _, [arg]}]}) do
    coeff_ast = quote_collect_terms_coeff(coeff)
    quote do: %OrTools.CpSat.Expr{special: [{:max, unquote(arg), unquote(coeff_ast)}]}
  end

  defp quote_collect_terms({:*, _, [{:max, _, [arg]}, coeff]}) do
    coeff_ast = quote_collect_terms_coeff(coeff)
    quote do: %OrTools.CpSat.Expr{special: [{:max, unquote(arg), unquote(coeff_ast)}]}
  end

  # coeff * div(a, b)
  defp quote_collect_terms({:*, _, [coeff, {:div, _, [dividend, divisor]}]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    coeff_ast = quote_collect_terms_coeff(coeff)

    quote do: %OrTools.CpSat.Expr{
            special: [{:div, unquote(dividend_ast), unquote(divisor_ast), unquote(coeff_ast)}]
          }
  end

  defp quote_collect_terms({:*, _, [{:div, _, [dividend, divisor]}, coeff]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    coeff_ast = quote_collect_terms_coeff(coeff)

    quote do: %OrTools.CpSat.Expr{
            special: [{:div, unquote(dividend_ast), unquote(divisor_ast), unquote(coeff_ast)}]
          }
  end

  # coeff * pow(base, exp)
  defp quote_collect_terms({:*, _, [coeff, {:pow, _, [base, exp]}]})
       when is_integer(exp) and exp >= 2 do
    base_ast = quote_collect_terms(base)
    coeff_ast = quote_collect_terms_coeff(coeff)

    quote do: %OrTools.CpSat.Expr{
            special: [{:pow, unquote(base_ast), unquote(exp), unquote(coeff_ast)}]
          }
  end

  defp quote_collect_terms({:*, _, [{:pow, _, [base, exp]}, coeff]})
       when is_integer(exp) and exp >= 2 do
    base_ast = quote_collect_terms(base)
    coeff_ast = quote_collect_terms_coeff(coeff)

    quote do: %OrTools.CpSat.Expr{
            special: [{:pow, unquote(base_ast), unquote(exp), unquote(coeff_ast)}]
          }
  end

  # coeff * abs(expr)
  defp quote_collect_terms({:*, _, [coeff, {:abs, _, [inner]}]}) do
    inner_ast = quote_collect_terms(inner)
    coeff_ast = quote_collect_terms_coeff(coeff)
    quote do: %OrTools.CpSat.Expr{special: [{:abs, unquote(inner_ast), unquote(coeff_ast)}]}
  end

  defp quote_collect_terms({:*, _, [{:abs, _, [inner]}, coeff]}) do
    inner_ast = quote_collect_terms(inner)
    coeff_ast = quote_collect_terms_coeff(coeff)
    quote do: %OrTools.CpSat.Expr{special: [{:abs, unquote(inner_ast), unquote(coeff_ast)}]}
  end

  # var * var — nonlinear multiplication
  defp quote_collect_terms({:*, _, [left, right]}) when is_atom(left) and is_atom(right) do
    left_expr = Macro.escape(%Expr{terms: [{left, 1}]})
    right_expr = Macro.escape(%Expr{terms: [{right, 1}]})
    quote do: %OrTools.CpSat.Expr{special: [{:mul, unquote(left_expr), unquote(right_expr), 1}]}
  end

  # coeff * var — both literals
  defp quote_collect_terms({:*, _, [coeff, var]}) when is_integer(coeff) and is_atom(var) do
    Macro.escape(%Expr{terms: [{var, coeff}]})
  end

  # var * coeff — both literals
  defp quote_collect_terms({:*, _, [var, coeff]}) when is_atom(var) and is_integer(coeff) do
    Macro.escape(%Expr{terms: [{var, coeff}]})
  end

  # coeff * expr or expr * coeff — at least one side is a runtime expression
  defp quote_collect_terms({:*, _, [left, right]}) do
    cond do
      is_integer(left) ->
        quote do: OrTools.CpSat.Expr.scale(OrTools.CpSat.Expr.new(unquote(right)), unquote(left))

      is_integer(right) ->
        quote do: OrTools.CpSat.Expr.scale(OrTools.CpSat.Expr.new(unquote(left)), unquote(right))

      is_atom(left) ->
        left_expr = Macro.escape(%Expr{terms: [{left, 1}]})

        quote do
          right_value = unquote(right)

          if is_atom(right_value) do
            %OrTools.CpSat.Expr{
              special: [{:mul, unquote(left_expr), OrTools.CpSat.Expr.new(right_value), 1}]
            }
          else
            OrTools.CpSat.Expr.scale(unquote(left_expr), right_value)
          end
        end

      is_atom(right) ->
        right_expr = Macro.escape(%Expr{terms: [{right, 1}]})

        quote do
          left_value = unquote(left)

          if is_atom(left_value) do
            %OrTools.CpSat.Expr{
              special: [{:mul, OrTools.CpSat.Expr.new(left_value), unquote(right_expr), 1}]
            }
          else
            OrTools.CpSat.Expr.scale(unquote(right_expr), left_value)
          end
        end

      true ->
        quote do
          left_value = unquote(left)
          right_value = unquote(right)

          cond do
            is_atom(left_value) and is_atom(right_value) ->
              %OrTools.CpSat.Expr{
                special: [{:mul, OrTools.CpSat.Expr.new(left_value), OrTools.CpSat.Expr.new(right_value), 1}]
              }

            is_atom(left_value) ->
              OrTools.CpSat.Expr.scale(OrTools.CpSat.Expr.new(left_value), right_value)

            true ->
              OrTools.CpSat.Expr.scale(OrTools.CpSat.Expr.new(right_value), left_value)
          end
        end
    end
  end

  # Literal atom (e.g. :x)
  defp quote_collect_terms(var) when is_atom(var) do
    Macro.escape(%Expr{terms: [{var, 1}]})
  end

  # Literal integer (e.g. 50)
  defp quote_collect_terms(int) when is_integer(int) do
    Macro.escape(%Expr{const: int})
  end

  # Runtime expression — could be a variable name (atom), a constant (integer), or an Expr
  defp quote_collect_terms(other) do
    quote do: OrTools.CpSat.Expr.new(unquote(other))
  end

  # Helper: extract coefficient value from AST (literal int or runtime expression)
  defp quote_collect_terms_coeff(coeff), do: coeff

  defimpl Collectable do
    alias OrTools.CpSat.Constraint
    alias OrTools.CpSat.Variable

    def into(model) do
      fun = fn
        # Variable struct - store directly
        acc, {:cont, %Variable{} = variable} ->
          Map.update!(acc, :vars, &(&1 ++ [variable]))

        # Constraint struct - store directly
        acc, {:cont, %Constraint{} = constraint} ->
          Map.update!(acc, :constraints, &(&1 ++ [constraint]))

        # List of Variable or Constraint structs
        acc, {:cont, items} when is_list(items) ->
          Enum.reduce(items, acc, fn
            %Variable{} = variable, model -> Map.update!(model, :vars, &(&1 ++ [variable]))
            %Constraint{} = constraint, model -> Map.update!(model, :constraints, &(&1 ++ [constraint]))
          end)

        acc, :done ->
          acc

        _acc, :halt ->
          :ok
      end

      {model, fun}
    end

  end
end
