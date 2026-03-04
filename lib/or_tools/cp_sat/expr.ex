defmodule OrTools.CpSat.Expr do
  @moduledoc """
  An expression in a CP-SAT model.

  Represents a linear combination of variables, a constant offset, and
  special non-linear terms (abs, pow, mul, div, min, max) that will be
  linearized when building constraints or objectives.

  Created via `CpSat.expr/1` and `CpSat.sum/1`. Composable at runtime:

      score = CpSat.expr(2 * :x + 3 * :y)
      penalty = CpSat.expr(-pow(:z, 2))
      total = CpSat.sum([score, penalty])
  """

  defstruct terms: [], const: 0, special: []

  @type t :: %__MODULE__{
          terms: [{atom(), integer()}],
          const: integer(),
          special: [special_term()]
        }

  @type special_term ::
          {:abs, t(), integer()}
          | {:pow, t(), pos_integer(), integer()}
          | {:mul, t(), t(), integer()}
          | {:div, t(), t(), integer()}
          | {:min, [atom()], integer()}
          | {:max, [atom()], integer()}

  @doc false
  def new, do: %__MODULE__{}
  def new(%__MODULE__{} = expr), do: expr
  def new(name) when is_atom(name), do: %__MODULE__{terms: [{name, 1}]}
  def new(value) when is_integer(value), do: %__MODULE__{const: value}

  def new({name, coeff}) when is_atom(name) and is_integer(coeff),
    do: %__MODULE__{terms: [{name, coeff}]}

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

  defp scale_special({:abs, inner, coeff}, factor), do: {:abs, inner, coeff * factor}
  defp scale_special({:pow, base, exp, coeff}, factor), do: {:pow, base, exp, coeff * factor}
  defp scale_special({:mul, left, right, coeff}, factor), do: {:mul, left, right, coeff * factor}

  defp scale_special({:div, dividend, divisor, coeff}, factor),
    do: {:div, dividend, divisor, coeff * factor}

  defp scale_special({:min, vars, coeff}, factor), do: {:min, vars, coeff * factor}
  defp scale_special({:max, vars, coeff}, factor), do: {:max, vars, coeff * factor}

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
    defp format_special({:pow, _inner, exp, coeff}), do: {coeff, "pow(..., #{exp})"}
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
end
