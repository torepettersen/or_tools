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
  alias OrTools.CpSat.Objective
  alias OrTools.CpSat.Score
  alias OrTools.CpSat.Solver
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
  def new do
    %__MODULE__{}
  end

  # --- Variable creation ---

  @doc "Creates a boolean (0/1) variable with the given name."
  defdelegate bool_var(name), to: Variable, as: :bool

  @doc "Adds a boolean (0/1) variable to a model."
  def bool_var(%__MODULE__{} = model, name) when is_atom(name) do
    add_vars(model, bool_var(name))
  end

  @doc "Creates boolean (0/1) variables for each name in the list."
  defdelegate bool_vars(names), to: Variable

  @doc "Adds boolean (0/1) variables for each name in the list to a model."
  def bool_vars(%__MODULE__{} = model, names) when is_list(names) do
    add_vars(model, bool_vars(names))
  end

  @doc "Creates an integer variable with the given name and range."
  defdelegate int_var(name, range), to: Variable, as: :int

  @doc "Adds an integer variable to a model."
  def int_var(%__MODULE__{} = model, name, %Range{} = range) when is_atom(name) do
    add_vars(model, int_var(name, range))
  end

  defdelegate int_var(name, lower_bound, upper_bound), to: Variable, as: :int

  def int_var(%__MODULE__{} = model, name, lower_bound, upper_bound) when is_atom(name) do
    add_vars(model, int_var(name, lower_bound, upper_bound))
  end

  @doc "Creates integer variables with the given range for each name in the list."
  defdelegate int_vars(names, range), to: Variable

  @doc "Adds integer variables with the given range for each name in the list to a model."
  def int_vars(%__MODULE__{} = model, names, %Range{} = range) when is_list(names) do
    add_vars(model, int_vars(names, range))
  end

  @doc "Creates an interval variable defined by start, duration, and end variables."
  defdelegate interval_var(name, start_name, duration_name, end_name), to: Constraint, as: :interval

  def interval_var(%Variable{name: start_name}, name, duration, %Variable{name: end_name})
      when is_atom(name) and is_integer(duration) do
    Constraint.interval_fixed(name, start_name, duration, end_name)
  end

  @doc "Adds an interval variable to a model."
  def interval_var(%__MODULE__{} = model, name, start_name, duration_name, end_name)
      when is_atom(start_name) do
    add(model, interval_var(name, start_name, duration_name, end_name))
  end

  def interval_var(%__MODULE__{} = model, name, %Variable{} = start_var, duration, %Variable{} = end_var)
      when is_integer(duration) do
    add_vars(model, interval_var(start_var, name, duration, end_var))
  end

  # --- Model building ---

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
    Map.put(model, :objective, Objective.merge_score(model.objective, new_terms))
  end

  @doc "Reads the solved value of a variable from a result by Variable struct."
  def value(result, %Variable{name: name}) do
    result.values[name]
  end

  # --- Constraints ---

  @doc "Creates a no-overlap constraint: no two interval variables overlap in time."
  defdelegate no_overlap(intervals), to: Constraint

  @doc "Adds a no-overlap constraint to a model."
  def no_overlap(%__MODULE__{} = model, intervals) when is_list(intervals) do
    add(model, no_overlap(intervals))
  end

  @doc "Creates a max-equality constraint: target = max(var_names)."
  def max_eq(target, var_names) when is_atom(target) and is_list(var_names) do
    Constraint.max_eq(target, Variable.resolve_names(var_names))
  end

  def max_eq(%Variable{name: target_name}, var_names) when is_list(var_names) do
    max_eq(target_name, var_names)
  end

  @doc "Adds a max-equality constraint to a model."
  def max_eq(%__MODULE__{} = model, target, var_names) do
    add(model, max_eq(target, var_names))
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
    Constraint.build_constrain_ast(expr)
  end

  @doc """
  Adds a linear constraint. Does not validate variable names.

  ## Examples

      CpSat.constrain(model, 2 * :x + 7 * :y <= 50)
  """
  defmacro constrain(model, expr) do
    Constraint.build_constrain_ast(model, expr)
  end

  @doc """
  Creates an all-different constraint. Does not validate variable names.

  Each item can be a variable name (atom) or an `Expr` (single variable with
  a constant offset). Useful for diagonal constraints:

      CpSat.all_different(Enum.map(board_range, fn i -> CpSat.expr(:"q\#{i}" + i) end))

  Returns a `Constraint` struct that can be collected into a model.
  """
  def all_different(items) when is_list(items) do
    Constraint.all_different(Enum.map(items, &Expr.to_name_offset/1))
  end

  @doc "Adds an all-different constraint to a model."
  def all_different(%__MODULE__{} = model, items) when is_list(items) do
    add(model, all_different(items))
  end

  @doc "Constrains exactly one of the given boolean variables to be true."
  defdelegate exactly_one(var_names), to: Constraint

  def exactly_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, exactly_one(var_names))
  end

  @doc "Constrains at most one of the given boolean variables to be true."
  defdelegate at_most_one(var_names), to: Constraint

  def at_most_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, at_most_one(var_names))
  end

  @doc "Constrains at least one of the given boolean variables to be true."
  defdelegate at_least_one(var_names), to: Constraint

  def at_least_one(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, at_least_one(var_names))
  end

  @doc "Constrains the boolean AND of the given variables to be true."
  defdelegate bool_and(var_names), to: Constraint

  def bool_and(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, bool_and(var_names))
  end

  @doc "Constrains the boolean OR of the given variables to be true."
  defdelegate bool_or(var_names), to: Constraint

  def bool_or(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, bool_or(var_names))
  end

  @doc "Constrains the boolean XOR of the given variables to be true."
  defdelegate bool_xor(var_names), to: Constraint

  def bool_xor(%__MODULE__{} = model, var_names) when is_list(var_names) do
    add(model, bool_xor(var_names))
  end

  # --- Expressions ---

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
  def expr do
    %Expr{}
  end

  # --- Objective ---

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
    Objective.build_score_ast(expr)
  end

  defmacro score(model, expr) do
    Objective.build_score_ast(model, expr)
  end

  @doc """
  Sets the objective to maximize.

  With an expression, sets the objective immediately. Does not validate variable names.

  Without an expression, sets the direction for scores accumulated via `CpSat.score/1`.
  Can be called before or after scores are added.
  """
  defmacro maximize(model, expr) do
    Objective.build_objective_ast(model, :maximize, expr)
  end

  def maximize(%__MODULE__{} = model) do
    Map.put(model, :objective, Objective.set_direction(model.objective, :maximize))
  end

  @doc """
  Sets the objective to minimize.

  With an expression, sets the objective immediately. Does not validate variable names.

  Without an expression, sets the direction for scores accumulated via `CpSat.score/1`.
  Can be called before or after scores are added.
  """
  defmacro minimize(model, expr) do
    Objective.build_objective_ast(model, :minimize, expr)
  end

  def minimize(%__MODULE__{} = model) do
    Map.put(model, :objective, Objective.set_direction(model.objective, :minimize))
  end

  @doc false
  def __build_objective__(%__MODULE__{} = model, sense, %Expr{} = expr) do
    {model, linear_terms} = flatten_expr(model, expr)
    Map.put(model, :objective, {sense, Expr.merge_terms(linear_terms)})
  end

  # --- Solving ---

  @doc """
  Validates and solves the model. Returns `{:ok, result}` or `{:error, reason}`.

  Always validates variable names before calling the solver.

  ## Options

      CpSat.solve(model, params: [max_time_in_seconds: 10.0, num_workers: 4])

  Supported params: `max_time_in_seconds`, `max_number_of_conflicts`, `num_workers`,
  `random_seed`, `log_search_progress`.
  """
  defdelegate solve(model, opts \\ []), to: Solver

  @doc """
  Validates and solves the model. Returns the result or raises on error.

  See `solve/2` for options.
  """
  defdelegate solve!(model, opts \\ []), to: Solver

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
  defdelegate solve_all(model, opts \\ []), to: Solver

  @doc """
  Enumerates all solutions. Returns the result or raises on error.

  See `solve_all/2` for options.
  """
  defdelegate solve_all!(model, opts \\ []), to: Solver

  # --- Validation ---

  @doc """
  Validates the model without solving. Returns `:ok` or `{:error, reason}`.
  """
  def validate(%__MODULE__{} = model) do
    declared = MapSet.new(model.vars, fn %Variable{name: name} -> name end)

    with :ok <- Constraint.validate_all(model.constraints, declared),
         :ok <- Objective.validate(model.objective, declared) do
      :ok
    end
  end

  # --- Private helpers ---

  # Linearizes an %Expr{} into {model, [{atom, int}]} by applying aux vars/constraints.
  defp flatten_expr(model, %Expr{} = expr) do
    var_bounds = Variable.bounds_map(model.vars)
    {linear_terms, additions} = Expr.linearize(expr, var_bounds)

    model =
      Enum.reduce(Enum.reverse(additions), model, fn {var, constraint}, m ->
        m |> add(var) |> add(constraint)
      end)

    {model, linear_terms}
  end

  # Adds vars (or a single var) to a model and returns {updated_model, vars}.
  defp add_vars(model, vars) do
    {add(model, vars), vars}
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
