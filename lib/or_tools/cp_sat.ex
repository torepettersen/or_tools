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

  @doc "Adds an integer variable with the given name and range."
  def int_var(%__MODULE__{} = model, name, %Range{first: lb, last: ub}) when is_atom(name) do
    %{model | vars: model.vars ++ [{name, lb, ub}]}
  end

  def int_var(%__MODULE__{} = model, name, lb, ub) when is_atom(name) do
    %{model | vars: model.vars ++ [{name, lb, ub}]}
  end

  @doc """
  Adds a linear constraint. Does not validate variable names.

  Use `constrain!/2` to validate immediately.

  ## Examples

      CpSat.constrain(model, 2 * :x + 7 * :y <= 50)
  """
  defmacro constrain(model, expr) do
    {terms, op, rhs} = parse_constraint(expr)

    quote do
      OrTools.CpSat.add_constraint(unquote(model), unquote(terms), unquote(op), unquote(rhs))
    end
  end

  @doc """
  Adds a linear constraint with immediate validation.

  Raises `ArgumentError` if any variable in the expression is not declared.

  ## Examples

      CpSat.constrain!(model, 2 * :x + 7 * :y <= 50)
  """
  defmacro constrain!(model, expr) do
    {terms, op, rhs} = parse_constraint(expr)

    quote do
      OrTools.CpSat.add_constraint!(unquote(model), unquote(terms), unquote(op), unquote(rhs))
    end
  end

  @doc false
  def add_constraint(%__MODULE__{} = model, terms, op, rhs) do
    %{model | constraints: model.constraints ++ [{terms, op, rhs}]}
  end

  @doc false
  def add_constraint!(%__MODULE__{} = model, terms, op, rhs) do
    validate_terms!(model, terms)
    add_constraint(model, terms, op, rhs)
  end

  @doc """
  Adds an all-different constraint. Does not validate variable names.

  Use `all_different!/2` to validate immediately.
  """
  def all_different(%__MODULE__{} = model, var_names) when is_list(var_names) do
    %{model | constraints: model.constraints ++ [{:all_different, var_names}]}
  end

  @doc """
  Adds an all-different constraint with immediate validation.

  Raises `ArgumentError` if any variable name is not declared.
  """
  def all_different!(%__MODULE__{} = model, var_names) when is_list(var_names) do
    validate_var_names!(model, var_names)
    all_different(model, var_names)
  end

  @doc "Sets the objective to maximize. Does not validate variable names."
  defmacro maximize(model, expr) do
    terms = parse_linear_expr(expr)

    quote do
      OrTools.CpSat.set_objective(unquote(model), :maximize, unquote(terms))
    end
  end

  @doc "Sets the objective to maximize with immediate validation."
  defmacro maximize!(model, expr) do
    terms = parse_linear_expr(expr)

    quote do
      OrTools.CpSat.set_objective!(unquote(model), :maximize, unquote(terms))
    end
  end

  @doc "Sets the objective to minimize. Does not validate variable names."
  defmacro minimize(model, expr) do
    terms = parse_linear_expr(expr)

    quote do
      OrTools.CpSat.set_objective(unquote(model), :minimize, unquote(terms))
    end
  end

  @doc "Sets the objective to minimize with immediate validation."
  defmacro minimize!(model, expr) do
    terms = parse_linear_expr(expr)

    quote do
      OrTools.CpSat.set_objective!(unquote(model), :minimize, unquote(terms))
    end
  end

  @doc false
  def set_objective(%__MODULE__{} = model, sense, terms) do
    %{model | objective: {sense, terms}}
  end

  @doc false
  def set_objective!(%__MODULE__{} = model, sense, terms) do
    validate_terms!(model, terms)
    set_objective(model, sense, terms)
  end

  @doc """
  Validates and solves the model. Returns `{:ok, result}` or `{:error, reason}`.

  Always validates variable names before calling the solver.
  """
  def solve(%__MODULE__{} = model) do
    case validate(model) do
      :ok ->
        {status, values, objective} =
          OrTools.NIF.solve(model.vars, model.constraints, model.objective)

        {:ok, %{status: status, values: values, objective: objective}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates and solves the model. Returns the result or raises on error.
  """
  def solve!(%__MODULE__{} = model) do
    case solve(model) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
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
    MapSet.new(vars, &elem(&1, 0))
  end

  defp validate_constraints([], _declared), do: :ok

  defp validate_constraints([constraint | rest], declared) do
    case validate_constraint(constraint, declared) do
      :ok -> validate_constraints(rest, declared)
      error -> error
    end
  end

  defp validate_constraint({terms, _op, _rhs}, declared) do
    check_terms(terms, declared)
  end

  defp validate_constraint({:all_different, var_names}, declared) do
    check_var_names(var_names, declared)
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

  defp validate_terms!(%__MODULE__{} = model, terms) do
    declared = declared_var_names(model)

    case check_terms(terms, declared) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp validate_var_names!(%__MODULE__{} = model, names) do
    declared = declared_var_names(model)

    case check_var_names(names, declared) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, message
    end
  end

  # --- Macro helpers (compile-time AST parsing) ---

  defp parse_constraint({op, _, [lhs, rhs]}) when op in [:<=, :>=, :==, :!=, :<, :>] do
    lhs_terms = collect_terms(lhs)
    rhs_terms = collect_terms(rhs)

    {lhs_vars, lhs_const} = split_terms(lhs_terms)
    {rhs_vars, rhs_const} = split_terms(rhs_terms)

    final_vars = merge_terms(lhs_vars, negate_terms(rhs_vars))
    final_rhs = rhs_const - lhs_const

    {final_vars, op, final_rhs}
  end

  defp parse_linear_expr(expr) do
    terms = collect_terms(expr)
    {vars, _const} = split_terms(terms)
    vars
  end

  defp collect_terms({:+, _, [left, right]}) do
    collect_terms(left) ++ collect_terms(right)
  end

  defp collect_terms({:-, _, [left, right]}) do
    collect_terms(left) ++ negate_collected(collect_terms(right))
  end

  defp collect_terms({:-, _, [operand]}) do
    negate_collected(collect_terms(operand))
  end

  defp collect_terms({:*, _, [coeff, var]}) when is_atom(var) and is_integer(coeff) do
    [{var, coeff}]
  end

  defp collect_terms({:*, _, [var, coeff]}) when is_atom(var) and is_integer(coeff) do
    [{var, coeff}]
  end

  defp collect_terms(var) when is_atom(var) do
    [{var, 1}]
  end

  defp collect_terms(int) when is_integer(int) do
    [{:__const__, int}]
  end

  defp negate_collected(terms) do
    Enum.map(terms, fn {var, coeff} -> {var, -coeff} end)
  end

  defp split_terms(terms) do
    {consts, vars} = Enum.split_with(terms, fn {name, _} -> name == :__const__ end)
    const_sum = consts |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    {vars, const_sum}
  end

  defp negate_terms(terms) do
    Enum.map(terms, fn {var, coeff} -> {var, -coeff} end)
  end

  defp merge_terms(a, b) do
    (a ++ b)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {var, coeffs} -> {var, Enum.sum(coeffs)} end)
    |> Enum.reject(fn {_, coeff} -> coeff == 0 end)
  end
end
