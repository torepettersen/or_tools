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

  @doc "Adds a boolean (0/1) variable with the given name."
  def bool_var(%__MODULE__{} = model, name) when is_atom(name) do
    %{model | vars: model.vars ++ [{name, 0, 1}]}
  end

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
    {lhs_ast, op, rhs_ast} = parse_constraint_ast(expr)

    quote do
      {terms, op, rhs} =
        OrTools.CpSat.__build_constraint__(unquote(lhs_ast), unquote(rhs_ast), unquote(op))

      OrTools.CpSat.add_constraint(unquote(model), terms, op, rhs)
    end
  end

  @doc """
  Adds a linear constraint with immediate validation.

  Raises `ArgumentError` if any variable in the expression is not declared.

  ## Examples

      CpSat.constrain!(model, 2 * :x + 7 * :y <= 50)
  """
  defmacro constrain!(model, expr) do
    {lhs_ast, op, rhs_ast} = parse_constraint_ast(expr)

    quote do
      {terms, op, rhs} =
        OrTools.CpSat.__build_constraint__(unquote(lhs_ast), unquote(rhs_ast), unquote(op))

      OrTools.CpSat.add_constraint!(unquote(model), terms, op, rhs)
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

  @doc """
  Returns the raw term list for an expression, without a model.

  Useful for building expressions in variables before passing to
  `maximize`, `minimize`, or `constrain`.

  ## Examples

      terms = CpSat.expr(2 * :x + 3 * :y)
      CpSat.maximize(model, sum(terms))
  """
  defmacro expr(expression) do
    quote_collect_terms(expression)
  end

  @doc """
  Converts a list of variable names, `{name, coeff}` tuples, or expr results
  into a flat term list at runtime.

  ## Examples

      terms = CpSat.sum(for v <- vars, do: CpSat.expr(2 * v))
      CpSat.maximize(model, terms)
  """
  def sum(list) when is_list(list) do
    list
    |> List.flatten()
    |> Enum.map(fn
      {:__abs__, _inner, _coeff} = abs_term -> abs_term
      {:__pow__, _inner, _exp, _coeff} = pow_term -> pow_term
      {:__mul__, _left, _right, _coeff} = mul_term -> mul_term
      {:__div__, _dividend, _divisor, _coeff} = div_term -> div_term
      {name, coeff} when is_atom(name) and is_integer(coeff) -> {name, coeff}
      name when is_atom(name) -> {name, 1}
    end)
  end

  @doc "Sets the objective to maximize. Does not validate variable names."
  defmacro maximize(model, expr) do
    terms_ast = quote_collect_terms(expr)

    quote do
      OrTools.CpSat.__build_objective__(unquote(model), :maximize, unquote(terms_ast))
    end
  end

  @doc "Sets the objective to maximize with immediate validation."
  defmacro maximize!(model, expr) do
    terms_ast = quote_collect_terms(expr)

    quote do
      model = OrTools.CpSat.__build_objective__(unquote(model), :maximize, unquote(terms_ast))
      OrTools.CpSat.__validate_objective__!(model)
      model
    end
  end

  @doc "Sets the objective to minimize. Does not validate variable names."
  defmacro minimize(model, expr) do
    terms_ast = quote_collect_terms(expr)

    quote do
      OrTools.CpSat.__build_objective__(unquote(model), :minimize, unquote(terms_ast))
    end
  end

  @doc "Sets the objective to minimize with immediate validation."
  defmacro minimize!(model, expr) do
    terms_ast = quote_collect_terms(expr)

    quote do
      model = OrTools.CpSat.__build_objective__(unquote(model), :minimize, unquote(terms_ast))
      OrTools.CpSat.__validate_objective__!(model)
      model
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

  @doc false
  def __validate_objective__!(%__MODULE__{} = model) do
    case model.objective do
      {_sense, terms} -> validate_terms!(model, terms)
      nil -> :ok
    end
  end

  @doc false
  def __negate_raw_terms__(terms) do
    Enum.map(terms, fn
      {:__abs__, inner, coeff} -> {:__abs__, inner, -coeff}
      {:__pow__, inner, exp, coeff} -> {:__pow__, inner, exp, -coeff}
      {:__mul__, left, right, coeff} -> {:__mul__, left, right, -coeff}
      {:__div__, dividend, divisor, coeff} -> {:__div__, dividend, divisor, -coeff}
      {v, c} -> {v, -c}
    end)
  end

  @doc false
  def __build_objective__(%__MODULE__{} = model, sense, raw_terms) do
    {model, flat_terms} = flatten_special_terms(model, raw_terms, sense)
    {vars, _const} = split_terms(flat_terms)
    set_objective(model, sense, vars)
  end

  defp flatten_special_terms(model, terms, _sense) do
    var_bounds = Map.new(model.vars, fn {name, lb, ub} -> {name, {lb, ub}} end)

    Enum.reduce(terms, {model, []}, fn
      {:__abs__, inner_terms, coeff}, {model, acc} ->
        abs_name = :"__abs_#{:erlang.unique_integer([:positive])}"
        {inner_vars, inner_const} = split_terms(inner_terms)

        max_bound =
          Enum.sum_by(inner_vars, fn {name, c} ->
            {lb, ub} = Map.get(var_bounds, name, {0, 0})
            max(abs(lb * c), abs(ub * c))
          end) + abs(inner_const)

        model = int_var(model, abs_name, 0, max_bound)

        model = %{
          model
          | constraints: model.constraints ++ [{:abs_eq, abs_name, inner_vars, inner_const}]
        }

        {model, [{abs_name, coeff} | acc]}

      {:__pow__, base_terms, exponent, coeff}, {model, acc} ->
        {base_vars, _base_const} = split_terms(base_terms)

        # For pow we need a single variable as the base (e.g. :x, not :x + :y)
        # We support single-variable bases only
        [{base_var, base_coeff}] = base_vars

        {lb, ub} = Map.get(var_bounds, base_var, {0, 0})
        effective_lb = lb * base_coeff
        effective_ub = ub * base_coeff

        # Chain multiplications: x^2 = x*x, x^3 = (x*x)*x, etc.
        # First, create a scaled base variable if coeff != 1
        {model, var_bounds, source_var} =
          if base_coeff == 1 do
            {model, var_bounds, base_var}
          else
            scaled_name = :"__pow_base_#{:erlang.unique_integer([:positive])}"
            scaled_lb = min(effective_lb, effective_ub)
            scaled_ub = max(effective_lb, effective_ub)
            model = int_var(model, scaled_name, scaled_lb, scaled_ub)
            var_bounds = Map.put(var_bounds, scaled_name, {scaled_lb, scaled_ub})

            model = %{
              model
              | constraints:
                  model.constraints ++ [{[{base_var, base_coeff}], :==, 0, scaled_name}]
            }

            {model, var_bounds, scaled_name}
          end

        # Chain: aux1 = source * source, aux2 = aux1 * source, ...
        {model, _var_bounds, result_var} =
          Enum.reduce(2..exponent, {model, var_bounds, source_var}, fn i, {model, vb, prev_var} ->
            pow_name = :"__pow_#{:erlang.unique_integer([:positive])}"

            {prev_lb, prev_ub} = Map.get(vb, prev_var, {0, 0})
            {src_lb, src_ub} = Map.get(vb, source_var, {0, 0})

            products = [prev_lb * src_lb, prev_lb * src_ub, prev_ub * src_lb, prev_ub * src_ub]
            pow_lb = Enum.min(products)
            pow_ub = Enum.max(products)

            model = int_var(model, pow_name, pow_lb, pow_ub)
            vb = Map.put(vb, pow_name, {pow_lb, pow_ub})

            factors =
              if i == 2,
                do: [source_var, source_var],
                else: [prev_var, source_var]

            model = %{
              model
              | constraints: model.constraints ++ [{:mul_eq, pow_name, factors}]
            }

            {model, vb, pow_name}
          end)

        {model, [{result_var, coeff} | acc]}

      {:__mul__, left_terms, right_terms, coeff}, {model, acc} ->
        [{left_var, 1}] = elem(split_terms(left_terms), 0)
        [{right_var, 1}] = elem(split_terms(right_terms), 0)

        {lb_l, ub_l} = Map.get(var_bounds, left_var, {0, 0})
        {lb_r, ub_r} = Map.get(var_bounds, right_var, {0, 0})
        products = for l <- [lb_l, ub_l], r <- [lb_r, ub_r], do: l * r

        mul_name = :"__mul_#{:erlang.unique_integer([:positive])}"
        model = int_var(model, mul_name, Enum.min(products), Enum.max(products))

        model = %{
          model
          | constraints: model.constraints ++ [{:mul_eq, mul_name, [left_var, right_var]}]
        }

        {model, [{mul_name, coeff} | acc]}

      {:__div__, dividend_terms, divisor_terms, coeff}, {model, acc} ->
        [{dividend_var, 1}] = elem(split_terms(dividend_terms), 0)
        [{divisor_var, 1}] = elem(split_terms(divisor_terms), 0)

        {lb_n, ub_n} = Map.get(var_bounds, dividend_var, {0, 0})
        {lb_d, ub_d} = Map.get(var_bounds, divisor_var, {1, 1})

        quotients =
          for n <- [lb_n, ub_n], d <- [lb_d, ub_d], d != 0, do: Kernel.div(n, d)

        div_name = :"__div_#{:erlang.unique_integer([:positive])}"
        model = int_var(model, div_name, Enum.min(quotients), Enum.max(quotients))

        model = %{
          model
          | constraints: model.constraints ++ [{:div_eq, div_name, dividend_var, divisor_var}]
        }

        {model, [{div_name, coeff} | acc]}

      term, {model, acc} ->
        {model, [term | acc]}
    end)
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

        visible_values =
          Map.reject(values, fn {name, _} ->
            s = Atom.to_string(name)

            String.starts_with?(s, "__abs_") or String.starts_with?(s, "__pow_") or
              String.starts_with?(s, "__mul_") or String.starts_with?(s, "__div_")
          end)

        {:ok, %{status: status, values: visible_values, objective: objective}}

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

  defp validate_constraint({:all_different, var_names}, declared) do
    check_var_names(var_names, declared)
  end

  defp validate_constraint({:abs_eq, target, terms, _const}, declared) do
    with :ok <- check_var_names([target], declared),
         :ok <- check_terms(terms, declared) do
      :ok
    end
  end

  defp validate_constraint({:mul_eq, target, factors}, declared) do
    check_var_names([target | factors], declared)
  end

  defp validate_constraint({:div_eq, target, dividend, divisor}, declared) do
    check_var_names([target, dividend, divisor], declared)
  end

  defp validate_constraint({terms, _op, _rhs}, declared) do
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

  # --- Runtime helpers for expression normalization ---

  @doc false
  def __build_constraint__(lhs_terms, rhs_terms, op) do
    {lhs_vars, lhs_const} = split_terms(lhs_terms)
    {rhs_vars, rhs_const} = split_terms(rhs_terms)

    final_vars = merge_terms(lhs_vars, negate_terms(rhs_vars))
    final_rhs = rhs_const - lhs_const

    {final_vars, op, final_rhs}
  end

  @doc false
  def __build_linear_expr__(terms) do
    {vars, _const} = split_terms(terms)
    vars
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

  # --- Macro helpers (compile-time AST → runtime code) ---

  defp parse_constraint_ast({op, _, [lhs, rhs]}) when op in [:<=, :>=, :==, :!=, :<, :>] do
    {quote_collect_terms(lhs), op, quote_collect_terms(rhs)}
  end

  # Generates quoted code that evaluates to a list of {atom | :__const__, integer} terms at runtime.
  defp quote_collect_terms({:+, _, [left, right]}) do
    l = quote_collect_terms(left)
    r = quote_collect_terms(right)
    quote do: unquote(l) ++ unquote(r)
  end

  defp quote_collect_terms({:-, _, [left, right]}) do
    l = quote_collect_terms(left)
    r = quote_collect_terms(right)
    quote do: unquote(l) ++ OrTools.CpSat.__negate_raw_terms__(unquote(r))
  end

  defp quote_collect_terms({:-, _, [operand]}) do
    o = quote_collect_terms(operand)
    quote do: OrTools.CpSat.__negate_raw_terms__(unquote(o))
  end

  # abs(expr) — emits a marker tuple that __build_objective__ will linearize
  defp quote_collect_terms({:abs, _, [inner]}) do
    inner_ast = quote_collect_terms(inner)
    quote do: [{:__abs__, unquote(inner_ast), 1}]
  end

  # div(dividend, divisor) — emits a marker tuple for integer division equality
  defp quote_collect_terms({:div, _, [dividend, divisor]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    quote do: [{:__div__, unquote(dividend_ast), unquote(divisor_ast), 1}]
  end

  # pow(expr, exponent) — emits a marker tuple for multiplication equality
  defp quote_collect_terms({:pow, _, [base, exp]}) when is_integer(exp) and exp >= 2 do
    base_ast = quote_collect_terms(base)
    quote do: [{:__pow__, unquote(base_ast), unquote(exp), 1}]
  end

  # sum(list) — accepts a list of atoms, {atom, coeff} tuples, expr results, or marker tuples
  defp quote_collect_terms({:sum, _, [arg]}) do
    quote do
      Enum.flat_map(unquote(arg), fn
        {:__abs__, _inner, _coeff} = abs_term -> [abs_term]
        {:__pow__, _inner, _exp, _coeff} = pow_term -> [pow_term]
        {:__mul__, _left, _right, _coeff} = mul_term -> [mul_term]
        {:__div__, _dividend, _divisor, _coeff} = div_term -> [div_term]
        {name, coeff} when is_atom(name) and is_integer(coeff) -> [{name, coeff}]
        name when is_atom(name) -> [{name, 1}]
        list when is_list(list) -> list
      end)
    end
  end

  # coeff * sum(list) or sum(list) * coeff — scale all terms
  defp quote_collect_terms({:*, _, [coeff, {:sum, _, _} = sum_expr]}) when is_integer(coeff) do
    sum_ast = quote_collect_terms(sum_expr)

    quote do
      Enum.map(unquote(sum_ast), fn
        {:__abs__, inner, c} -> {:__abs__, inner, c * unquote(coeff)}
        {:__pow__, inner, exp, c} -> {:__pow__, inner, exp, c * unquote(coeff)}
        {:__mul__, left, right, c} -> {:__mul__, left, right, c * unquote(coeff)}
        {:__div__, dividend, divisor, c} -> {:__div__, dividend, divisor, c * unquote(coeff)}
        {name, c} -> {name, c * unquote(coeff)}
      end)
    end
  end

  defp quote_collect_terms({:*, _, [{:sum, _, _} = sum_expr, coeff]}) when is_integer(coeff) do
    sum_ast = quote_collect_terms(sum_expr)

    quote do
      Enum.map(unquote(sum_ast), fn
        {:__abs__, inner, c} -> {:__abs__, inner, c * unquote(coeff)}
        {:__pow__, inner, exp, c} -> {:__pow__, inner, exp, c * unquote(coeff)}
        {:__mul__, left, right, c} -> {:__mul__, left, right, c * unquote(coeff)}
        {:__div__, dividend, divisor, c} -> {:__div__, dividend, divisor, c * unquote(coeff)}
        {name, c} -> {name, c * unquote(coeff)}
      end)
    end
  end

  # coeff * div(a, b) — scale the div marker's coefficient
  defp quote_collect_terms({:*, _, [coeff, {:div, _, [dividend, divisor]}]})
       when is_integer(coeff) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    quote do: [{:__div__, unquote(dividend_ast), unquote(divisor_ast), unquote(coeff)}]
  end

  defp quote_collect_terms({:*, _, [{:div, _, [dividend, divisor]}, coeff]})
       when is_integer(coeff) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    quote do: [{:__div__, unquote(dividend_ast), unquote(divisor_ast), unquote(coeff)}]
  end

  # runtime_coeff * div(a, b)
  defp quote_collect_terms({:*, _, [coeff, {:div, _, [dividend, divisor]}]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    quote do: [{:__div__, unquote(dividend_ast), unquote(divisor_ast), unquote(coeff)}]
  end

  defp quote_collect_terms({:*, _, [{:div, _, [dividend, divisor]}, coeff]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    quote do: [{:__div__, unquote(dividend_ast), unquote(divisor_ast), unquote(coeff)}]
  end

  # coeff * pow(expr, n) — scale the pow marker's coefficient
  defp quote_collect_terms({:*, _, [coeff, {:pow, _, [base, exp]}]})
       when is_integer(coeff) and is_integer(exp) and exp >= 2 do
    base_ast = quote_collect_terms(base)
    quote do: [{:__pow__, unquote(base_ast), unquote(exp), unquote(coeff)}]
  end

  defp quote_collect_terms({:*, _, [{:pow, _, [base, exp]}, coeff]})
       when is_integer(coeff) and is_integer(exp) and exp >= 2 do
    base_ast = quote_collect_terms(base)
    quote do: [{:__pow__, unquote(base_ast), unquote(exp), unquote(coeff)}]
  end

  # runtime_coeff * pow(expr, n)
  defp quote_collect_terms({:*, _, [coeff, {:pow, _, [base, exp]}]})
       when is_integer(exp) and exp >= 2 do
    base_ast = quote_collect_terms(base)
    quote do: [{:__pow__, unquote(base_ast), unquote(exp), unquote(coeff)}]
  end

  defp quote_collect_terms({:*, _, [{:pow, _, [base, exp]}, coeff]})
       when is_integer(exp) and exp >= 2 do
    base_ast = quote_collect_terms(base)
    quote do: [{:__pow__, unquote(base_ast), unquote(exp), unquote(coeff)}]
  end

  # coeff * abs(expr) — scale the abs marker's coefficient
  defp quote_collect_terms({:*, _, [coeff, {:abs, _, [inner]}]}) when is_integer(coeff) do
    inner_ast = quote_collect_terms(inner)
    quote do: [{:__abs__, unquote(inner_ast), unquote(coeff)}]
  end

  defp quote_collect_terms({:*, _, [{:abs, _, [inner]}, coeff]}) when is_integer(coeff) do
    inner_ast = quote_collect_terms(inner)
    quote do: [{:__abs__, unquote(inner_ast), unquote(coeff)}]
  end

  # runtime_coeff * abs(expr) — coeff is a runtime expression
  defp quote_collect_terms({:*, _, [coeff, {:abs, _, [inner]}]}) do
    inner_ast = quote_collect_terms(inner)
    quote do: [{:__abs__, unquote(inner_ast), unquote(coeff)}]
  end

  defp quote_collect_terms({:*, _, [{:abs, _, [inner]}, coeff]}) do
    inner_ast = quote_collect_terms(inner)
    quote do: [{:__abs__, unquote(inner_ast), unquote(coeff)}]
  end

  # var * var where both are literal atoms — nonlinear multiplication
  defp quote_collect_terms({:*, _, [left, right]}) when is_atom(left) and is_atom(right) do
    Macro.escape([{:__mul__, [{left, 1}], [{right, 1}], 1}])
  end

  # coeff * var where both are literals
  defp quote_collect_terms({:*, _, [coeff, var]}) when is_integer(coeff) and is_atom(var) do
    [{var, coeff}]
  end

  # var * coeff where both are literals
  defp quote_collect_terms({:*, _, [var, coeff]}) when is_atom(var) and is_integer(coeff) do
    [{var, coeff}]
  end

  # coeff * expr or expr * coeff — at least one side is a runtime expression
  defp quote_collect_terms({:*, _, [left, right]}) do
    cond do
      is_integer(left) ->
        # left is a literal integer, right is a runtime expression (variable name)
        quote do: [{unquote(right), unquote(left)}]

      is_integer(right) ->
        # right is a literal integer, left is a runtime expression (variable name)
        quote do: [{unquote(left), unquote(right)}]

      is_atom(left) ->
        # left is a literal atom, right could be a runtime var or coefficient
        quote do
          r_val = unquote(right)

          if is_atom(r_val),
            do: [{:__mul__, [{unquote(left), 1}], [{r_val, 1}], 1}],
            else: [{unquote(left), r_val}]
        end

      is_atom(right) ->
        # right is a literal atom, left could be a runtime var or coefficient
        quote do
          l_val = unquote(left)

          if is_atom(l_val),
            do: [{:__mul__, [{l_val, 1}], [{unquote(right), 1}], 1}],
            else: [{unquote(right), l_val}]
        end

      true ->
        # Both sides are runtime expressions
        quote do
          l_val = unquote(left)
          r_val = unquote(right)

          cond do
            is_atom(l_val) and is_atom(r_val) ->
              [{:__mul__, [{l_val, 1}], [{r_val, 1}], 1}]

            is_atom(l_val) ->
              [{l_val, r_val}]

            true ->
              [{r_val, l_val}]
          end
        end
    end
  end

  # Literal atom (e.g. :x)
  defp quote_collect_terms(var) when is_atom(var) do
    [{var, 1}]
  end

  # Literal integer (e.g. 50)
  defp quote_collect_terms(int) when is_integer(int) do
    [{:__const__, int}]
  end

  # Runtime expression — could be a variable name (atom), a constant (integer), or a term list
  defp quote_collect_terms(other) do
    quote do
      case unquote(other) do
        val when is_atom(val) -> [{val, 1}]
        val when is_integer(val) -> [{:__const__, val}]
        val when is_list(val) -> val
      end
    end
  end
end
