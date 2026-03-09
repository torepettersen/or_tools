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
  alias OrTools.CpSat.Score
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
  def bool_var(name) when is_atom(name), do: Variable.bool(name)

  def bool_var(%__MODULE__{} = model, name) when is_atom(name) do
    var = bool_var(name)
    {add(model, var), var}
  end

  @doc "Creates boolean (0/1) variables for each name in the list."
  def bool_vars(names) when is_list(names), do: Enum.map(names, &bool_var/1)

  @doc "Adds boolean (0/1) variables for each name in the list to a model."
  def bool_vars(%__MODULE__{} = model, names) when is_list(names) do
    vars = bool_vars(names)
    {add(model, vars), vars}
  end

  @doc "Creates an integer variable with the given name and range."
  def int_var(name, %Range{} = range) when is_atom(name), do: Variable.int(name, range)

  def int_var(name, lower_bound, upper_bound)
      when is_atom(name) and is_integer(lower_bound) and is_integer(upper_bound),
      do: Variable.int(name, lower_bound, upper_bound)

  @doc "Adds an integer variable to a model."
  def int_var(%__MODULE__{} = model, name, %Range{} = range) when is_atom(name) do
    var = int_var(name, range)
    {add(model, var), var}
  end

  def int_var(%__MODULE__{} = model, name, lower_bound, upper_bound) when is_atom(name) do
    var = int_var(name, lower_bound, upper_bound)
    {add(model, var), var}
  end

  @doc "Creates integer variables with the given range for each name in the list."
  def int_vars(names, %Range{} = range) when is_list(names), do: Enum.map(names, &int_var(&1, range))

  @doc "Adds integer variables with the given range for each name in the list to a model."
  def int_vars(%__MODULE__{} = model, names, %Range{} = range) when is_list(names) do
    vars = int_vars(names, range)
    {add(model, vars), vars}
  end

  @doc "Creates an interval variable defined by start, duration, and end variables."
  def interval_var(name, start_name, duration_name, end_name)
      when is_atom(name) and is_atom(start_name) and is_atom(duration_name) and is_atom(end_name),
      do: Constraint.interval(name, start_name, duration_name, end_name)

  def interval_var(%Variable{name: start_name}, name, duration, %Variable{name: end_name})
      when is_atom(name) and is_integer(duration),
      do: Constraint.interval_fixed(name, start_name, duration, end_name)

  @doc "Adds an interval variable to a model."
  def interval_var(%__MODULE__{} = model, name, start_name, duration_name, end_name)
      when is_atom(start_name) do
    add(model, interval_var(name, start_name, duration_name, end_name))
  end

  def interval_var(%__MODULE__{} = model, name, %Variable{} = start_var, duration, %Variable{} = end_var)
      when is_integer(duration) do
    interval = interval_var(start_var, name, duration, end_var)
    {add(model, interval), interval}
  end

  @doc "Adds a variable or constraint (or list thereof) to a model without returning the item."
  def add(%__MODULE__{} = model, %Variable{} = var) do
    Map.update!(model, :vars, &(&1 ++ [var]))
  end

  def add(%__MODULE__{} = model, %Constraint{} = constraint) do
    Map.update!(model, :constraints, &(&1 ++ [constraint]))
  end

  def add(%__MODULE__{} = model, items) when is_list(items) do
    Enum.reduce(items, model, &add(&2, &1))
  end

  def add(%__MODULE__{} = model, %Score{expr: expr}) do
    {model, new_terms} = flatten_expr(model, expr)

    case model.objective do
      nil ->
        Map.put(model, :objective, {nil, new_terms})

      {sense, existing_terms} ->
        Map.put(model, :objective, {sense, Expr.merge_terms(existing_terms ++ new_terms)})
    end
  end

  @doc "Reads the solved value of a variable from a result by Variable struct."
  def value(result, %Variable{name: name}), do: result.values[name]

  @doc "Creates a no-overlap constraint: no two interval variables overlap in time."
  def no_overlap(intervals) when is_list(intervals) do
    names =
      Enum.map(intervals, fn
        name when is_atom(name) -> name
        %Constraint{data: {name, _, _, _}} -> name
      end)

    Constraint.no_overlap(names)
  end

  @doc "Adds a no-overlap constraint to a model."
  def no_overlap(%__MODULE__{} = model, intervals) when is_list(intervals) do
    add(model, no_overlap(intervals))
  end

  @doc "Creates a max-equality constraint: target = max(var_names)."
  def max_eq(target, var_names) when is_atom(target) and is_list(var_names) do
    Constraint.max_eq(target, resolve_var_names(var_names))
  end

  def max_eq(%Variable{name: target_name}, var_names) when is_list(var_names) do
    max_eq(target_name, var_names)
  end

  @doc "Adds a max-equality constraint to a model."
  def max_eq(%__MODULE__{} = model, target, var_names) do
    add(model, max_eq(target, var_names))
  end

  defp resolve_var_names(items) do
    Enum.map(items, fn
      %Variable{name: name} -> name
      name when is_atom(name) -> name
    end)
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
    {lhs_ast, op, rhs_ast} = Expr.parse_constraint_ast(expr)

    quote do
      {terms, op, rhs} =
        OrTools.CpSat.Expr.build_constraint_terms(unquote(lhs_ast), unquote(rhs_ast), unquote(op))

      OrTools.CpSat.Constraint.linear(terms, op, rhs)
    end
  end

  @doc """
  Adds a linear constraint. Does not validate variable names.

  ## Examples

      CpSat.constrain(model, 2 * :x + 7 * :y <= 50)
  """
  defmacro constrain(model, expr) do
    {lhs_ast, op, rhs_ast} = Expr.parse_constraint_ast(expr)

    quote do
      {terms, op, rhs} =
        OrTools.CpSat.Expr.build_constraint_terms(unquote(lhs_ast), unquote(rhs_ast), unquote(op))

      OrTools.CpSat.add_constraint(unquote(model), terms, op, rhs)
    end
  end

  @doc false
  def add_constraint(%__MODULE__{} = model, terms, op, rhs) do
    add(model, Constraint.linear(terms, op, rhs))
  end

  @doc """
  Creates an all-different constraint. Does not validate variable names.

  Each item can be a variable name (atom) or an `Expr` (single variable with
  a constant offset). Useful for diagonal constraints:

      CpSat.all_different(Enum.map(board_range, fn i -> CpSat.expr(:"q\#{i}" + i) end))

  Returns a `Constraint` struct that can be collected into a model.
  """
  def all_different(items) when is_list(items) do
    name_offsets =
      Enum.map(items, fn
        name when is_atom(name) -> {name, 0}
        %Expr{terms: [{name, 1}], const: offset, special: []} -> {name, offset}
      end)

    Constraint.all_different(name_offsets)
  end

  @doc "Adds an all-different constraint to a model."
  def all_different(%__MODULE__{} = model, items) when is_list(items) do
    add(model, all_different(items))
  end

  @doc "Constrains exactly one of the given boolean variables to be true."
  def exactly_one(var_names) when is_list(var_names), do: Constraint.exactly_one(var_names)

  def exactly_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, exactly_one(var_names))
  end

  @doc "Constrains at most one of the given boolean variables to be true."
  def at_most_one(var_names) when is_list(var_names), do: Constraint.at_most_one(var_names)

  def at_most_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, at_most_one(var_names))
  end

  @doc "Constrains at least one of the given boolean variables to be true."
  def at_least_one(var_names) when is_list(var_names), do: Constraint.at_least_one(var_names)

  def at_least_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, at_least_one(var_names))
  end

  @doc "Constrains the boolean AND of the given variables to be true."
  def bool_and(var_names) when is_list(var_names), do: Constraint.bool_and(var_names)

  def bool_and(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, bool_and(var_names))
  end

  @doc "Constrains the boolean OR of the given variables to be true."
  def bool_or(var_names) when is_list(var_names), do: Constraint.bool_or(var_names)

  def bool_or(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, bool_or(var_names))
  end

  @doc "Constrains the boolean XOR of the given variables to be true."
  def bool_xor(var_names) when is_list(var_names), do: Constraint.bool_xor(var_names)

  def bool_xor(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, bool_xor(var_names))
  end

  @doc """
  Builds an `%Expr{}` from a mathematical expression.

  ## Examples

      iex> CpSat.expr(2 * :x + 3 * :y)
      #Expr<2*x + 3*y>
  """
  defmacro expr(expression) do
    Expr.quote_collect_terms(expression)
  end

  @doc """
  Returns a zero expression. Use with `into:` to collect expressions:

      for emp <- employees, into: CpSat.expr() do
        score(model, emp)
      end
  """
  def expr, do: %Expr{}

  @doc """
  Builds an objective score contribution without adding it to a model.

  Returns a `Score` struct that can be collected into a model via `into: model`
  or `CpSat.add(model, ...)`. Scores accumulate into the model's objective.
  The direction is set separately with `CpSat.maximize/1` or `CpSat.minimize/1`.

  ## Example

      def contracted_fulfillment(model, employees, shifts) do
        # ... add vars and constraints ...
        CpSat.add(model, CpSat.score(1000 * :contracted_fulfillment))
      end

      def fairness(model, employees, shifts) do
        for a <- employees, b <- employees, a.id < b.id, into: model do
          CpSat.score(-abs(sum(employee_hours(a, shifts)) - sum(employee_hours(b, shifts))))
        end
      end

      CpSat.new()
      |> contracted_fulfillment(employees, shifts)
      |> fairness(employees, shifts)
      |> CpSat.maximize()
      |> CpSat.solve!()
  """
  defmacro score(expr) do
    terms_ast = Expr.quote_collect_terms(expr)
    quote do: %OrTools.CpSat.Score{expr: unquote(terms_ast)}
  end

  defmacro score(model, expr) do
    terms_ast = Expr.quote_collect_terms(expr)
    quote do: OrTools.CpSat.add(unquote(model), %OrTools.CpSat.Score{expr: unquote(terms_ast)})
  end

  @doc """
  Sets the objective to maximize.

  With an expression, sets the objective immediately. Does not validate variable names.

  Without an expression, sets the direction for scores accumulated via `CpSat.score/1`.
  Can be called before or after scores are added.
  """
  defmacro maximize(model, expr) do
    terms_ast = Expr.quote_collect_terms(expr)

    quote do
      OrTools.CpSat.__build_objective__(unquote(model), :maximize, unquote(terms_ast))
    end
  end

  def maximize(%__MODULE__{} = model) do
    case model.objective do
      nil -> Map.put(model, :objective, {:maximize, []})
      {_sense, terms} -> Map.put(model, :objective, {:maximize, terms})
    end
  end

  @doc """
  Sets the objective to minimize.

  With an expression, sets the objective immediately. Does not validate variable names.

  Without an expression, sets the direction for scores accumulated via `CpSat.score/1`.
  Can be called before or after scores are added.
  """
  defmacro minimize(model, expr) do
    terms_ast = Expr.quote_collect_terms(expr)

    quote do
      OrTools.CpSat.__build_objective__(unquote(model), :minimize, unquote(terms_ast))
    end
  end

  def minimize(%__MODULE__{} = model) do
    case model.objective do
      nil -> Map.put(model, :objective, {:minimize, []})
      {_sense, terms} -> Map.put(model, :objective, {:minimize, terms})
    end
  end

  @doc false
  def set_objective(%__MODULE__{} = model, sense, terms) do
    Map.put(model, :objective, {sense, terms})
  end

  @doc false
  def __build_objective__(%__MODULE__{} = model, sense, %Expr{} = expr) do
    {model, linear_terms} = flatten_expr(model, expr)
    set_objective(model, sense, Expr.merge_terms(linear_terms))
  end

  # Linearizes an %Expr{} into {model, [{atom, int}]} by delegating special-term
  # linearization to Expr.linearize/2 and applying the resulting aux vars/constraints.
  defp flatten_expr(model, %Expr{} = expr) do
    var_bounds = Variable.bounds_map(model.vars)
    {linear_terms, additions} = Expr.linearize(expr, var_bounds)

    model =
      Enum.reduce(Enum.reverse(additions), model, fn {var, constraint}, m ->
        m |> add(var) |> add(constraint)
      end)

    {model, linear_terms}
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

        vars_tuples = Enum.map(model.vars, &Variable.to_tuple/1)
        constraints_tuples = Enum.map(model.constraints, &Constraint.to_tuple/1)

        {status, values, objective} =
          OrTools.NIF.solve(vars_tuples, constraints_tuples, model.objective, params)

        {:ok, %{status: status, values: Variable.filter_internal(values), objective: objective}}

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
        var_names =
          model.vars
          |> Enum.map(fn %Variable{name: name} -> name end)
          |> Enum.reject(&Variable.internal?/1)

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

        vars_tuples = Enum.map(model.vars, &Variable.to_tuple/1)
        constraints_tuples = Enum.map(model.constraints, &Constraint.to_tuple/1)

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
          Enum.map(raw_solutions, fn {values, objective} ->
            %{values: Variable.filter_internal(values), objective: objective}
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
    internal_names = Variable.internal_names(model.vars)

    spawn(fn ->
      solution_handler_loop(callback, internal_names, init_state, ctrl)
    end)
  end

  defp solution_handler_loop(callback, internal_names, state, ctrl) do
    receive do
      {:solution, _index, values, objective} ->
        solution = %{values: Variable.reject_internal(values, internal_names), objective: objective}

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

  @doc """
  Validates the model without solving. Returns `:ok` or `{:error, reason}`.
  """
  def validate(%__MODULE__{} = model) do
    declared = MapSet.new(model.vars, fn %Variable{name: name} -> name end)

    with :ok <- validate_constraints(model.constraints, declared),
         :ok <- validate_objective(model.objective, declared) do
      :ok
    end
  end

  defp validate_constraints([], _declared), do: :ok

  defp validate_constraints([%Constraint{} = constraint | rest], declared) do
    case Constraint.validate(constraint, declared) do
      :ok -> validate_constraints(rest, declared)
      error -> error
    end
  end

  defp validate_objective(nil, _declared), do: :ok

  defp validate_objective({nil, _terms}, _declared) do
    {:error, "score expressions were added but CpSat.maximize/1 or CpSat.minimize/1 was never called"}
  end

  defp validate_objective({_sense, terms}, declared) do
    check_terms(terms, declared)
  end

  defp check_terms(terms, declared) do
    unknown =
      terms
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&MapSet.member?(declared, &1))

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

  defimpl Collectable do
    def into(model) do
      fun = fn
        acc, {:cont, item} -> OrTools.CpSat.add(acc, item)
        acc, :done -> acc
        _acc, :halt -> :ok
      end

      {model, fun}
    end
  end
end
