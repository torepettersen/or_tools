defmodule OrTools.CpSat.Expr do
  @moduledoc """
  An expression in a CP-SAT model.

  Represents a linear combination of variables, a constant offset, and
  special non-linear terms (abs, mul, div, min, max) that will be
  linearized when building constraints or objectives.

  Created via `CpSat.expr/1`. Composable at runtime:

      score = CpSat.expr(2 * :x + 3 * :y)
      penalty = CpSat.expr(-abs(:z))
      total = CpSat.expr(score + penalty)
  """

  alias OrTools.CpSat.Constraint
  alias OrTools.CpSat.Variable

  defstruct terms: [], const: 0, special: []

  @type t :: %__MODULE__{
          terms: [{atom(), integer()}],
          const: integer(),
          special: [special_term()]
        }

  @type special_term ::
          {:abs, t(), integer()}
          | {:mul, t(), t(), integer()}
          | {:div, t(), t(), integer()}
          | {:min, [atom()], integer()}
          | {:max, [atom()], integer()}

  @doc false
  def new do
    %__MODULE__{}
  end

  def new(%__MODULE__{} = expr) do
    expr
  end

  def new(%Variable{name: name}) do
    %__MODULE__{terms: [{name, 1}]}
  end

  def new(name) when is_atom(name) do
    %__MODULE__{terms: [{name, 1}]}
  end

  def new(value) when is_integer(value) do
    %__MODULE__{const: value}
  end

  def new({name, coeff}) when is_atom(name) and is_integer(coeff) do
    %__MODULE__{terms: [{name, coeff}]}
  end

  @doc false
  def add(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      terms: a.terms ++ b.terms,
      const: a.const + b.const,
      special: a.special ++ b.special
    }
  end

  @doc false
  def subtract(%__MODULE__{} = a, %__MODULE__{} = b) do
    add(a, negate(b))
  end

  @doc false
  def sum(%__MODULE__{} = expr) do
    expr
  end

  def sum(list) when is_list(list) do
    list
    |> List.flatten()
    |> Enum.reduce(%__MODULE__{}, fn item, acc -> add(acc, new(item)) end)
  end

  @doc false
  def negate(%__MODULE__{} = expr) do
    scale(expr, -1)
  end

  @doc false
  def scale(%__MODULE__{} = expr, factor) when is_integer(factor) do
    %__MODULE__{
      terms: Enum.map(expr.terms, fn {v, c} -> {v, c * factor} end),
      const: expr.const * factor,
      special: Enum.map(expr.special, &scale_special(&1, factor))
    }
  end

  defp scale_special({:abs, inner, coeff}, factor) do
    {:abs, inner, coeff * factor}
  end

  defp scale_special({:mul, left, right, coeff}, factor) do
    {:mul, left, right, coeff * factor}
  end

  defp scale_special({:div, dividend, divisor, coeff}, factor) do
    {:div, dividend, divisor, coeff * factor}
  end

  defp scale_special({:min, vars, coeff}, factor) do
    {:min, vars, coeff * factor}
  end

  defp scale_special({:max, vars, coeff}, factor) do
    {:max, vars, coeff * factor}
  end

  # --- Linear term utilities ---

  @doc false
  def merge_terms(terms) do
    terms
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {var, coeffs} -> {var, Enum.sum(coeffs)} end)
    |> Enum.reject(fn {_, coeff} -> coeff == 0 end)
  end

  # --- Expression linearization ---

  # Converts an Expr's special (nonlinear) terms into linear terms plus a list of
  # {Variable, Constraint} pairs representing the required auxiliary variables and
  # constraints that must be added to the model.
  @doc false
  def linearize(%__MODULE__{terms: terms, special: special}, var_bounds) do
    Enum.reduce(special, {terms, []}, fn
      {:abs, %__MODULE__{} = inner, coeff}, {acc_terms, additions} ->
        abs_name = :"__abs_#{:erlang.unique_integer([:positive])}"

        max_bound =
          Enum.sum_by(inner.terms, fn {name, c} ->
            {lb, ub} = Map.get(var_bounds, name, {0, 0})
            max(abs(lb * c), abs(ub * c))
          end) + abs(inner.const)

        var = Variable.int(abs_name, 0, max_bound)
        constraint = Constraint.abs_eq(abs_name, inner.terms, inner.const)
        {[{abs_name, coeff} | acc_terms], [{var, constraint} | additions]}

      {:mul, %__MODULE__{} = left, %__MODULE__{} = right, coeff}, {acc_terms, additions} ->
        [{left_var, 1}] = left.terms
        [{right_var, 1}] = right.terms
        {ll, lu} = Map.get(var_bounds, left_var, {0, 0})
        {rl, ru} = Map.get(var_bounds, right_var, {0, 0})
        products = for l <- [ll, lu], r <- [rl, ru], do: l * r
        mul_name = :"__mul_#{:erlang.unique_integer([:positive])}"
        var = Variable.int(mul_name, Enum.min(products), Enum.max(products))
        constraint = Constraint.mul_eq(mul_name, [left_var, right_var])
        {[{mul_name, coeff} | acc_terms], [{var, constraint} | additions]}

      {:min, var_names, coeff}, {acc_terms, additions} ->
        bounds = Enum.map(var_names, &Map.get(var_bounds, &1, {0, 0}))
        min_name = :"__min_#{:erlang.unique_integer([:positive])}"
        lower = bounds |> Enum.min_by(&elem(&1, 0)) |> elem(0)
        upper = bounds |> Enum.min_by(&elem(&1, 1)) |> elem(1)
        var = Variable.int(min_name, lower, upper)
        constraint = Constraint.min_eq(min_name, var_names)
        {[{min_name, coeff} | acc_terms], [{var, constraint} | additions]}

      {:max, var_names, coeff}, {acc_terms, additions} ->
        bounds = Enum.map(var_names, &Map.get(var_bounds, &1, {0, 0}))
        max_name = :"__max_#{:erlang.unique_integer([:positive])}"
        lower = bounds |> Enum.max_by(&elem(&1, 0)) |> elem(0)
        upper = bounds |> Enum.max_by(&elem(&1, 1)) |> elem(1)
        var = Variable.int(max_name, lower, upper)
        constraint = Constraint.max_eq(max_name, var_names)
        {[{max_name, coeff} | acc_terms], [{var, constraint} | additions]}

      {:div, %__MODULE__{} = dividend_expr, %__MODULE__{} = divisor_expr, coeff},
      {acc_terms, additions} ->
        [{dividend_var, 1}] = dividend_expr.terms
        [{divisor_var, 1}] = divisor_expr.terms
        {dl, du} = Map.get(var_bounds, dividend_var, {0, 0})
        {vl, vu} = Map.get(var_bounds, divisor_var, {1, 1})
        quotients = for n <- [dl, du], d <- [vl, vu], d != 0, do: Kernel.div(n, d)
        div_name = :"__div_#{:erlang.unique_integer([:positive])}"
        var = Variable.int(div_name, Enum.min(quotients), Enum.max(quotients))
        constraint = Constraint.div_eq(div_name, dividend_var, divisor_var)
        {[{div_name, coeff} | acc_terms], [{var, constraint} | additions]}
    end)
  end

  @doc "Converts an atom or single-variable Expr to a {name, offset} pair for all_different."
  def to_name_offset(name) when is_atom(name) do
    {name, 0}
  end

  def to_name_offset(%__MODULE__{terms: [{name, 1}], const: offset, special: []}) do
    {name, offset}
  end

  # --- Compile-time AST helpers (used by CpSat macros) ---

  # Addition
  @doc false
  def quote_collect_terms({:+, _, [left, right]}) do
    l = quote_collect_terms(left)
    r = quote_collect_terms(right)
    quote do: OrTools.CpSat.Expr.add(unquote(l), unquote(r))
  end

  # Subtraction
  def quote_collect_terms({:-, _, [left, right]}) do
    l = quote_collect_terms(left)
    r = quote_collect_terms(right)
    quote do: OrTools.CpSat.Expr.subtract(unquote(l), unquote(r))
  end

  # Unary negation
  def quote_collect_terms({:-, _, [operand]}) do
    o = quote_collect_terms(operand)
    quote do: OrTools.CpSat.Expr.negate(unquote(o))
  end

  # min(var_list) / max(var_list)
  def quote_collect_terms({:min, _, [arg]}) do
    quote do: %OrTools.CpSat.Expr{special: [{:min, unquote(arg), 1}]}
  end

  def quote_collect_terms({:max, _, [arg]}) do
    quote do: %OrTools.CpSat.Expr{special: [{:max, unquote(arg), 1}]}
  end

  # abs(expr)
  def quote_collect_terms({:abs, _, [inner]}) do
    inner_ast = quote_collect_terms(inner)
    quote do: %OrTools.CpSat.Expr{special: [{:abs, unquote(inner_ast), 1}]}
  end

  # div(dividend, divisor)
  def quote_collect_terms({:div, _, [dividend, divisor]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)

    quote do: %OrTools.CpSat.Expr{
            special: [{:div, unquote(dividend_ast), unquote(divisor_ast), 1}]
          }
  end

  # sum(list) — reduces a runtime list into a single Expr
  def quote_collect_terms({:sum, _, [arg]}) do
    quote do: OrTools.CpSat.Expr.sum(unquote(arg))
  end

  # coeff * sum(...)
  def quote_collect_terms({:*, _, [coeff, {:sum, _, _} = sum_expr]}) do
    sum_ast = quote_collect_terms(sum_expr)
    coeff_ast = coeff
    quote do: OrTools.CpSat.Expr.scale(unquote(sum_ast), unquote(coeff_ast))
  end

  def quote_collect_terms({:*, _, [{:sum, _, _} = sum_expr, coeff]}) do
    sum_ast = quote_collect_terms(sum_expr)
    coeff_ast = coeff
    quote do: OrTools.CpSat.Expr.scale(unquote(sum_ast), unquote(coeff_ast))
  end

  # coeff * min/max
  def quote_collect_terms({:*, _, [coeff, {:min, _, [arg]}]}) do
    coeff_ast = coeff
    quote do: %OrTools.CpSat.Expr{special: [{:min, unquote(arg), unquote(coeff_ast)}]}
  end

  def quote_collect_terms({:*, _, [{:min, _, [arg]}, coeff]}) do
    coeff_ast = coeff
    quote do: %OrTools.CpSat.Expr{special: [{:min, unquote(arg), unquote(coeff_ast)}]}
  end

  def quote_collect_terms({:*, _, [coeff, {:max, _, [arg]}]}) do
    coeff_ast = coeff
    quote do: %OrTools.CpSat.Expr{special: [{:max, unquote(arg), unquote(coeff_ast)}]}
  end

  def quote_collect_terms({:*, _, [{:max, _, [arg]}, coeff]}) do
    coeff_ast = coeff
    quote do: %OrTools.CpSat.Expr{special: [{:max, unquote(arg), unquote(coeff_ast)}]}
  end

  # coeff * div(a, b)
  def quote_collect_terms({:*, _, [coeff, {:div, _, [dividend, divisor]}]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    coeff_ast = coeff

    quote do: %OrTools.CpSat.Expr{
            special: [{:div, unquote(dividend_ast), unquote(divisor_ast), unquote(coeff_ast)}]
          }
  end

  def quote_collect_terms({:*, _, [{:div, _, [dividend, divisor]}, coeff]}) do
    dividend_ast = quote_collect_terms(dividend)
    divisor_ast = quote_collect_terms(divisor)
    coeff_ast = coeff

    quote do: %OrTools.CpSat.Expr{
            special: [{:div, unquote(dividend_ast), unquote(divisor_ast), unquote(coeff_ast)}]
          }
  end

  # coeff * abs(expr)
  def quote_collect_terms({:*, _, [coeff, {:abs, _, [inner]}]}) do
    inner_ast = quote_collect_terms(inner)
    coeff_ast = coeff
    quote do: %OrTools.CpSat.Expr{special: [{:abs, unquote(inner_ast), unquote(coeff_ast)}]}
  end

  def quote_collect_terms({:*, _, [{:abs, _, [inner]}, coeff]}) do
    inner_ast = quote_collect_terms(inner)
    coeff_ast = coeff
    quote do: %OrTools.CpSat.Expr{special: [{:abs, unquote(inner_ast), unquote(coeff_ast)}]}
  end

  # var * var — nonlinear multiplication
  def quote_collect_terms({:*, _, [left, right]}) when is_atom(left) and is_atom(right) do
    left_expr = Macro.escape(%__MODULE__{terms: [{left, 1}]})
    right_expr = Macro.escape(%__MODULE__{terms: [{right, 1}]})
    quote do: %OrTools.CpSat.Expr{special: [{:mul, unquote(left_expr), unquote(right_expr), 1}]}
  end

  # coeff * var — both literals
  def quote_collect_terms({:*, _, [coeff, var]}) when is_integer(coeff) and is_atom(var) do
    Macro.escape(%__MODULE__{terms: [{var, coeff}]})
  end

  # var * coeff — both literals
  def quote_collect_terms({:*, _, [var, coeff]}) when is_atom(var) and is_integer(coeff) do
    Macro.escape(%__MODULE__{terms: [{var, coeff}]})
  end

  # coeff * expr or expr * coeff — at least one side is a runtime expression
  def quote_collect_terms({:*, _, [left, right]}) do
    cond do
      is_integer(left) ->
        quote do: OrTools.CpSat.Expr.scale(OrTools.CpSat.Expr.new(unquote(right)), unquote(left))

      is_integer(right) ->
        quote do: OrTools.CpSat.Expr.scale(OrTools.CpSat.Expr.new(unquote(left)), unquote(right))

      is_atom(left) ->
        left_expr = Macro.escape(%__MODULE__{terms: [{left, 1}]})

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
        right_expr = Macro.escape(%__MODULE__{terms: [{right, 1}]})

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
                special: [
                  {:mul, OrTools.CpSat.Expr.new(left_value), OrTools.CpSat.Expr.new(right_value),
                   1}
                ]
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
  def quote_collect_terms(var) when is_atom(var) do
    Macro.escape(%__MODULE__{terms: [{var, 1}]})
  end

  # Literal integer (e.g. 50)
  def quote_collect_terms(int) when is_integer(int) do
    Macro.escape(%__MODULE__{const: int})
  end

  # Runtime expression — could be a variable name (atom), a constant (integer), or an Expr
  def quote_collect_terms(other) do
    quote do: OrTools.CpSat.Expr.new(unquote(other))
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{terms: terms, const: const, special: special}, _opts) do
      parts =
        Enum.map(special, &format_special/1) ++
          format_terms(terms) ++
          format_const(const)

      str =
        case parts do
          [] -> "0"
          _ -> join_parts(parts)
        end

      concat(["#Expr<", str, ">"])
    end

    defp format_special({:abs, _inner, coeff}), do: {coeff, "abs(...)"}
    defp format_special({:mul, _inner_l, _inner_r, coeff}), do: {coeff, "mul(...)"}
    defp format_special({:div, _inner_d, _inner_v, coeff}), do: {coeff, "div(...)"}
    defp format_special({:min, vars, coeff}), do: {coeff, "min(#{inspect_vars(vars)})"}
    defp format_special({:max, vars, coeff}), do: {coeff, "max(#{inspect_vars(vars)})"}

    defp inspect_vars(vars), do: Enum.map_join(vars, ", ", &Atom.to_string/1)

    defp format_terms(terms) do
      Enum.map(terms, fn {name, coeff} -> {coeff, Atom.to_string(name)} end)
    end

    defp format_const(0), do: []
    defp format_const(c), do: [{c, nil}]

    defp join_parts(parts) do
      parts
      |> Enum.with_index()
      |> Enum.map_join("", fn
        {{1, label}, 0} -> label || "1"
        {{-1, label}, 0} -> "-#{label || "1"}"
        {{c, label}, 0} when c > 0 -> "#{c}*#{label || ""}" |> String.trim_trailing("*")
        {{c, label}, 0} -> "#{c}*#{label || ""}" |> String.trim_trailing("*")
        {{1, label}, _} -> " + #{label || "1"}"
        {{-1, label}, _} -> " - #{label || "1"}"
        {{c, label}, _} when c > 0 -> " + #{c}*#{label || ""}" |> String.trim_trailing("*")
        {{c, label}, _} -> " - #{abs(c)}*#{label || ""}" |> String.trim_trailing("*")
      end)
    end
  end

  defimpl Collectable do
    def into(expr) do
      fun = fn
        acc, {:cont, item} -> OrTools.CpSat.Expr.add(acc, OrTools.CpSat.Expr.new(item))
        acc, :done -> acc
        _acc, :halt -> :ok
      end

      {expr, fun}
    end
  end
end
