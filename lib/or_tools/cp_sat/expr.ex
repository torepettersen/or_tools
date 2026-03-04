defmodule OrTools.CpSat.Expr do
  @moduledoc """
  An expression in a CP-SAT model.

  Represents a linear combination of variables, a constant offset, and
  special non-linear terms (abs, pow, mul, div, min, max) that will be
  linearized when building constraints or objectives.

  ## Examples

      iex> Expr.var(:x)
      #Expr<x>

      iex> Expr.add(Expr.var(:x), Expr.var(:y))
      #Expr<x + y>

      iex> Expr.scale(Expr.var(:x), 3)
      #Expr<3*x>
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

  @doc "Creates an empty expression (zero)."
  def new, do: %__MODULE__{}

  @doc "Creates an expression for a single variable with coefficient 1."
  def var(name) when is_atom(name), do: %__MODULE__{terms: [{name, 1}]}

  @doc "Creates a constant expression."
  def const(value) when is_integer(value), do: %__MODULE__{const: value}

  @doc "Adds two expressions."
  def add(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      terms: a.terms ++ b.terms,
      const: a.const + b.const,
      special: a.special ++ b.special
    }
  end

  @doc "Subtracts b from a."
  def subtract(%__MODULE__{} = a, %__MODULE__{} = b) do
    add(a, negate(b))
  end

  @doc "Negates an expression."
  def negate(%__MODULE__{} = expr) do
    scale(expr, -1)
  end

  @doc "Scales all terms in an expression by a factor."
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

  @doc """
  Coerces a value into an Expr.

  Handles: `%Expr{}`, atoms (variable names), integers (constants),
  and `{atom, integer}` tuples (weighted variables).
  """
  def coerce(%__MODULE__{} = expr), do: expr
  def coerce(name) when is_atom(name), do: var(name)
  def coerce(value) when is_integer(value), do: const(value)

  def coerce({name, coeff}) when is_atom(name) and is_integer(coeff),
    do: %__MODULE__{terms: [{name, coeff}]}

  @doc """
  Converts a runtime value (atom, integer, Expr, or legacy term list) into an Expr.

  Used in macro-generated code to handle values whose type is unknown at compile time.
  """
  def from_runtime(%__MODULE__{} = expr), do: expr
  def from_runtime(name) when is_atom(name), do: var(name)
  def from_runtime(value) when is_integer(value), do: const(value)
  def from_runtime(list) when is_list(list), do: from_raw(list)

  @doc """
  Converts from old raw term list format to Expr.

  Handles: `[{atom, int}]`, `[{:__pow__, ...}]`, etc.
  """
  def from_raw(terms) when is_list(terms) do
    Enum.reduce(terms, new(), fn
      {:__abs__, inner, coeff}, acc ->
        inner_expr = from_raw(inner)
        %{acc | special: acc.special ++ [{:abs, inner_expr, coeff}]}

      {:__pow__, base, exp, coeff}, acc ->
        base_expr = from_raw(base)
        %{acc | special: acc.special ++ [{:pow, base_expr, exp, coeff}]}

      {:__mul__, left, right, coeff}, acc ->
        left_expr = from_raw(left)
        right_expr = from_raw(right)
        %{acc | special: acc.special ++ [{:mul, left_expr, right_expr, coeff}]}

      {:__div__, dividend, divisor, coeff}, acc ->
        dividend_expr = from_raw(dividend)
        divisor_expr = from_raw(divisor)
        %{acc | special: acc.special ++ [{:div, dividend_expr, divisor_expr, coeff}]}

      {:__min__, vars, coeff}, acc ->
        %{acc | special: acc.special ++ [{:min, vars, coeff}]}

      {:__max__, vars, coeff}, acc ->
        %{acc | special: acc.special ++ [{:max, vars, coeff}]}

      {:__const__, value}, acc ->
        %{acc | const: acc.const + value}

      {name, coeff}, acc when is_atom(name) and is_integer(coeff) ->
        %{acc | terms: acc.terms ++ [{name, coeff}]}

      name, acc when is_atom(name) ->
        %{acc | terms: acc.terms ++ [{name, 1}]}
    end)
  end

  @doc """
  Converts an Expr back to the old raw term list format.

  Used at the boundary with flatten_special_terms and the NIF.
  """
  def to_raw(%__MODULE__{terms: terms, const: const, special: special}) do
    linear =
      terms ++
        if(const != 0, do: [{:__const__, const}], else: [])

    special_raw =
      Enum.map(special, fn
        {:abs, inner, coeff} ->
          {:__abs__, to_raw_linear(inner), coeff}

        {:pow, base, exp, coeff} ->
          {:__pow__, to_raw_linear(base), exp, coeff}

        {:mul, left, right, coeff} ->
          {:__mul__, to_raw_linear(left), to_raw_linear(right), coeff}

        {:div, dividend, divisor, coeff} ->
          {:__div__, to_raw_linear(dividend), to_raw_linear(divisor), coeff}

        {:min, vars, coeff} ->
          {:__min__, vars, coeff}

        {:max, vars, coeff} ->
          {:__max__, vars, coeff}
      end)

    linear ++ special_raw
  end

  # Converts an Expr to raw terms including constants as {:__const__, value}
  defp to_raw_linear(%__MODULE__{terms: terms, const: const, special: []}) do
    terms ++ if(const != 0, do: [{:__const__, const}], else: [])
  end

  defp to_raw_linear(%__MODULE__{} = expr) do
    to_raw(expr)
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
