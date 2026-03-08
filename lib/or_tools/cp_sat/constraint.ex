defmodule OrTools.CpSat.Constraint do
  @moduledoc false
  # Internal struct representing a constraint. Exposed via CpSat functions.

  defstruct [:type, :data]

  @type t :: %__MODULE__{
          type: constraint_type(),
          data: term()
        }

  @type constraint_type ::
          :linear
          | :exactly_one
          | :at_most_one
          | :at_least_one
          | :bool_and
          | :bool_or
          | :bool_xor
          | :all_different
          | :interval
          | :interval_fixed
          | :no_overlap

  @doc false
  def to_tuple(%__MODULE__{type: :linear, data: {terms, op, rhs}}), do: {terms, op, rhs}
  # Internal constraints used by flatten_expr
  def to_tuple(%__MODULE__{type: :abs_eq, data: {target, terms, const}}),
    do: {:abs_eq, target, terms, const}

  def to_tuple(%__MODULE__{type: :mul_eq, data: {target, var_names}}),
    do: {:mul_eq, target, var_names}

  def to_tuple(%__MODULE__{type: :min_eq, data: {target, var_names}}),
    do: {:min_eq, target, var_names}

  def to_tuple(%__MODULE__{type: :max_eq, data: {target, var_names}}),
    do: {:max_eq, target, var_names}

  def to_tuple(%__MODULE__{type: :div_eq, data: {target, dividend, divisor}}),
    do: {:div_eq, target, dividend, divisor}

  def to_tuple(%__MODULE__{type: :interval, data: {name, start_name, duration_name, end_name}}),
    do: {:interval, name, start_name, duration_name, end_name}

  def to_tuple(%__MODULE__{type: :interval_fixed, data: {name, start_name, duration, end_name}}),
    do: {:interval_fixed, name, start_name, duration, end_name}

  def to_tuple(%__MODULE__{type: type, data: data}), do: {type, data}

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{type: type, data: data}, _opts) do
      content = format_constraint(type, data)
      concat(["#Constraint<", content, ">"])
    end

    defp format_constraint(:exactly_one, vars) do
      "exactly_one(#{format_vars(vars)})"
    end

    defp format_constraint(:at_most_one, vars) do
      "at_most_one(#{format_vars(vars)})"
    end

    defp format_constraint(:at_least_one, vars) do
      "at_least_one(#{format_vars(vars)})"
    end

    defp format_constraint(:bool_and, vars) do
      "bool_and(#{format_vars(vars)})"
    end

    defp format_constraint(:bool_or, vars) do
      "bool_or(#{format_vars(vars)})"
    end

    defp format_constraint(:bool_xor, vars) do
      "bool_xor(#{format_vars(vars)})"
    end

    defp format_constraint(:all_different, name_offsets) do
      count = length(name_offsets)
      "all_different(#{count} items)"
    end

    defp format_constraint(:interval, {name, start_name, duration_name, end_name}) do
      "interval #{name}(#{start_name}, #{duration_name}, #{end_name})"
    end

    defp format_constraint(:interval_fixed, {name, start_name, duration, end_name}) do
      "interval #{name}(#{start_name}, fixed:#{duration}, #{end_name})"
    end

    defp format_constraint(:no_overlap, interval_names) do
      "no_overlap(#{format_vars(interval_names)})"
    end

    defp format_constraint(:linear, {terms, op, rhs}) do
      expr = format_terms(terms)
      "#{expr} #{op} #{rhs}"
    end

    defp format_vars(vars) when length(vars) <= 5 do
      Enum.map_join(vars, ", ", &inspect/1)
    end

    defp format_vars(vars) do
      "#{length(vars)} vars"
    end

    defp format_terms([]), do: "0"

    defp format_terms(terms) do
      terms
      |> Enum.with_index()
      |> Enum.map_join("", fn
        {{var, 1}, 0} -> Atom.to_string(var)
        {{var, -1}, 0} -> "-#{var}"
        {{var, coeff}, 0} when coeff > 0 -> "#{coeff}*#{var}"
        {{var, coeff}, 0} -> "#{coeff}*#{var}"
        {{var, 1}, _} -> " + #{var}"
        {{var, -1}, _} -> " - #{var}"
        {{var, coeff}, _} when coeff > 0 -> " + #{coeff}*#{var}"
        {{var, coeff}, _} -> " - #{abs(coeff)}*#{var}"
      end)
    end
  end
end
