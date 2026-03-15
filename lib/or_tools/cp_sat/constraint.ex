defmodule OrTools.CpSat.Constraint do
  @moduledoc false
  # Internal struct representing a constraint. Exposed via CpSat functions.

  alias OrTools.CpSat.Expr
  alias OrTools.CpSat.Variable

  defstruct [:type, :data]

  @type t :: %__MODULE__{
          type: constraint_type(),
          data: term()
        }

  @type constraint_type ::
          :linear
          | :all_different
          | :no_overlap
          | :min_eq
          | :max_eq
          | :mul_eq
          | :div_eq
          | :abs_eq
          | :exactly_one
          | :at_most_one
          | :at_least_one
          | :bool_and
          | :bool_or
          | :bool_xor

  # --- Constructors ---

  @doc false
  def linear(terms, op, rhs) do
    %__MODULE__{type: :linear, data: {terms, op, rhs}}
  end

  def all_different(items) when is_list(items) do
    %__MODULE__{type: :all_different, data: Enum.map(items, &Expr.to_name_offset/1)}
  end

  def no_overlap(intervals) when is_list(intervals) do
    %__MODULE__{type: :no_overlap, data: Enum.map(intervals, &interval_name/1)}
  end

  def min_eq(target, var_names) when is_atom(target) and is_list(var_names) do
    %__MODULE__{type: :min_eq, data: {target, Variable.resolve_names(var_names)}}
  end

  def min_eq(%Variable{name: target_name}, var_names) when is_list(var_names) do
    min_eq(target_name, var_names)
  end

  def max_eq(target, var_names) when is_atom(target) and is_list(var_names) do
    %__MODULE__{type: :max_eq, data: {target, Variable.resolve_names(var_names)}}
  end

  def max_eq(%Variable{name: target_name}, var_names) when is_list(var_names) do
    max_eq(target_name, var_names)
  end

  def mul_eq(target, var_names) do
    %__MODULE__{type: :mul_eq, data: {target, var_names}}
  end

  def div_eq(target, dividend, divisor) do
    %__MODULE__{type: :div_eq, data: {target, dividend, divisor}}
  end

  def abs_eq(target, var_name) when is_atom(target) and is_atom(var_name) do
    %__MODULE__{type: :abs_eq, data: {target, [{var_name, 1}], 0}}
  end

  def abs_eq(target, terms, const) do
    %__MODULE__{type: :abs_eq, data: {target, terms, const}}
  end

  def exactly_one(var_names) do
    %__MODULE__{type: :exactly_one, data: var_names}
  end

  def at_most_one(var_names) do
    %__MODULE__{type: :at_most_one, data: var_names}
  end

  def at_least_one(var_names) do
    %__MODULE__{type: :at_least_one, data: var_names}
  end

  def bool_and(var_names) do
    %__MODULE__{type: :bool_and, data: var_names}
  end

  def bool_or(var_names) do
    %__MODULE__{type: :bool_or, data: var_names}
  end

  def bool_xor(var_names) do
    %__MODULE__{type: :bool_xor, data: var_names}
  end

  defp interval_name(name) when is_atom(name), do: name
  defp interval_name(%Variable{name: name}), do: name

  # --- Compile-time AST helpers (used by CpSat constrain macros) ---

  @doc false
  def parse_constraint_ast({op, _, [lhs, rhs]}) when op in [:<=, :>=, :==, :!=, :<, :>] do
    {Expr.quote_collect_terms(lhs), op, Expr.quote_collect_terms(rhs)}
  end

  @doc false
  def build_constraint_terms(%Expr{} = lhs, %Expr{} = rhs, op) do
    combined = Expr.subtract(lhs, rhs)

    if combined.special != [] do
      raise ArgumentError,
            "constraints cannot contain nonlinear terms (abs, mul, div, min, max)"
    end

    {Expr.merge_terms(combined.terms), op, -combined.const}
  end

  @doc false
  def build_constrain_ast(expr) do
    {lhs_ast, op, rhs_ast} = parse_constraint_ast(expr)

    quote do
      {terms, op, rhs} =
        OrTools.CpSat.Constraint.build_constraint_terms(
          unquote(lhs_ast),
          unquote(rhs_ast),
          unquote(op)
        )

      OrTools.CpSat.Constraint.linear(terms, op, rhs)
    end
  end

  @doc false
  def build_constrain_ast(model, expr) do
    {lhs_ast, op, rhs_ast} = parse_constraint_ast(expr)

    quote do
      {terms, op, rhs} =
        OrTools.CpSat.Constraint.build_constraint_terms(
          unquote(lhs_ast),
          unquote(rhs_ast),
          unquote(op)
        )

      OrTools.CpSat.add(unquote(model), OrTools.CpSat.Constraint.linear(terms, op, rhs))
    end
  end

  # --- Validation ---

  @doc "Validates a list of constraints against declared variable names."
  def validate_all([], _declared) do
    :ok
  end

  def validate_all([%__MODULE__{} = constraint | rest], declared) do
    case validate(constraint, declared) do
      :ok -> validate_all(rest, declared)
      error -> error
    end
  end

  @doc "Validates that all variable names referenced by this constraint are declared."
  def validate(%__MODULE__{type: :linear, data: {terms, _op, _rhs}}, declared) do
    check_terms(terms, declared)
  end

  def validate(%__MODULE__{type: :all_different, data: name_offsets}, declared) do
    Enum.map(name_offsets, &elem(&1, 0)) |> check_var_names(declared)
  end

  def validate(%__MODULE__{type: :no_overlap}, _declared) do
    :ok
  end

  def validate(%__MODULE__{type: type, data: {target, var_names}}, declared)
      when type in [:min_eq, :max_eq, :mul_eq] do
    check_var_names([target | var_names], declared)
  end

  def validate(%__MODULE__{type: :div_eq, data: {target, dividend, divisor}}, declared) do
    check_var_names([target, dividend, divisor], declared)
  end

  def validate(%__MODULE__{type: :abs_eq, data: {target, terms, _const}}, declared) do
    with :ok <- check_var_names([target], declared),
         :ok <- check_terms(terms, declared),
         do: :ok
  end

  def validate(%__MODULE__{type: type, data: var_names}, declared)
      when type in [:exactly_one, :at_most_one, :at_least_one, :bool_and, :bool_or, :bool_xor] do
    check_var_names(var_names, declared)
  end

  defp check_terms(terms, declared) do
    Enum.map(terms, &elem(&1, 0)) |> check_var_names(declared)
  end

  defp check_var_names(names, declared) do
    case Enum.reject(names, &MapSet.member?(declared, &1)) do
      [] ->
        :ok

      unknown ->
        declared_list = declared |> MapSet.to_list() |> Enum.sort()

        {:error,
         "unknown variable(s) #{inspect(unknown)} in model. " <>
           "Declared variables: #{inspect(declared_list)}"}
    end
  end

  # --- Serialization ---

  @doc false
  def to_tuple(%__MODULE__{type: :linear, data: {terms, op, rhs}}) do
    {terms, op, rhs}
  end

  def to_tuple(%__MODULE__{type: :min_eq, data: {target, var_names}}) do
    {:min_eq, target, var_names}
  end

  def to_tuple(%__MODULE__{type: :max_eq, data: {target, var_names}}) do
    {:max_eq, target, var_names}
  end

  def to_tuple(%__MODULE__{type: :mul_eq, data: {target, var_names}}) do
    {:mul_eq, target, var_names}
  end

  def to_tuple(%__MODULE__{type: :div_eq, data: {target, dividend, divisor}}) do
    {:div_eq, target, dividend, divisor}
  end

  def to_tuple(%__MODULE__{type: :abs_eq, data: {target, terms, const}}) do
    {:abs_eq, target, terms, const}
  end

  def to_tuple(%__MODULE__{type: type, data: data}) do
    {type, data}
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{type: type, data: data}, _opts) do
      content = format_constraint(type, data)
      concat(["#Constraint<", content, ">"])
    end

    defp format_constraint(:linear, {terms, op, rhs}) do
      "#{format_terms(terms)} #{op} #{rhs}"
    end

    defp format_constraint(:all_different, name_offsets) do
      "all_different(#{name_offsets |> Enum.map(&elem(&1, 0)) |> format_vars()})"
    end

    defp format_constraint(:no_overlap, interval_names) do
      "no_overlap(#{format_vars(interval_names)})"
    end

    defp format_constraint(:min_eq, {target, var_names}) do
      "#{target} = min(#{format_vars(var_names)})"
    end

    defp format_constraint(:max_eq, {target, var_names}) do
      "#{target} = max(#{format_vars(var_names)})"
    end

    defp format_constraint(:mul_eq, {target, var_names}) do
      "#{target} = #{Enum.join(var_names, " * ")}"
    end

    defp format_constraint(:div_eq, {target, dividend, divisor}) do
      "#{target} = #{dividend} div #{divisor}"
    end

    defp format_constraint(:abs_eq, {target, terms, 0}) do
      "#{target} = abs(#{format_terms(terms)})"
    end

    defp format_constraint(:abs_eq, {target, terms, const}) do
      "#{target} = abs(#{format_terms(terms)} + #{const})"
    end

    defp format_constraint(:exactly_one, vars), do: "exactly_one(#{format_vars(vars)})"
    defp format_constraint(:at_most_one, vars), do: "at_most_one(#{format_vars(vars)})"
    defp format_constraint(:at_least_one, vars), do: "at_least_one(#{format_vars(vars)})"
    defp format_constraint(:bool_and, vars), do: "bool_and(#{format_vars(vars)})"
    defp format_constraint(:bool_or, vars), do: "bool_or(#{format_vars(vars)})"
    defp format_constraint(:bool_xor, vars), do: "bool_xor(#{format_vars(vars)})"

    defp format_vars(vars) when length(vars) <= 5 do
      Enum.map_join(vars, ", ", &inspect/1)
    end

    defp format_vars(vars) do
      "#{length(vars)} vars"
    end

    defp format_terms([]) do
      "0"
    end

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
