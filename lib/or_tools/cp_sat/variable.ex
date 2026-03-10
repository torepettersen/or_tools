defmodule OrTools.CpSat.Variable do
  @moduledoc false

  defstruct [:type, :name, :lower_bound, :upper_bound]

  @type t :: %__MODULE__{
          type: :bool | :int,
          name: atom(),
          lower_bound: integer() | nil,
          upper_bound: integer() | nil
        }

  @doc false
  def bool(name) when is_atom(name) do
    %__MODULE__{type: :bool, name: name}
  end

  @doc false
  def int(name, %Range{first: lower_bound, last: upper_bound}) when is_atom(name) do
    int(name, lower_bound, upper_bound)
  end

  def int(name, lower_bound, upper_bound)
      when is_atom(name) and is_integer(lower_bound) and is_integer(upper_bound) do
    %__MODULE__{type: :int, name: name, lower_bound: lower_bound, upper_bound: upper_bound}
  end

  @doc "Creates boolean (0/1) variables for each name in the list."
  def bool_vars(names) when is_list(names) do
    Enum.map(names, &bool/1)
  end

  @doc "Creates integer variables with the given range for each name in the list."
  def int_vars(names, %Range{} = range) when is_list(names) do
    Enum.map(names, &int(&1, range))
  end

  @doc "Extracts atom names from a list of atoms or Variable structs."
  def resolve_names(items) when is_list(items) do
    Enum.map(items, fn
      %__MODULE__{name: name} -> name
      name when is_atom(name) -> name
    end)
  end

  @doc false
  def to_tuple(%__MODULE__{type: :bool, name: name}) do
    {name, 0, 1}
  end

  def to_tuple(%__MODULE__{type: :int, name: name, lower_bound: lower_bound, upper_bound: upper_bound}) do
    {name, lower_bound, upper_bound}
  end

  @doc "Builds a map of variable name => {lower_bound, upper_bound} for all vars."
  def bounds_map(vars) when is_list(vars) do
    Map.new(vars, fn %__MODULE__{name: name, lower_bound: lower_bound, upper_bound: upper_bound} ->
      {name, {lower_bound || 0, upper_bound || 1}}
    end)
  end

  @doc "Returns true if the variable name was generated as an auxiliary (internal) variable."
  def internal?(name) when is_atom(name) do
    s = Atom.to_string(name)

    String.starts_with?(s, "__abs_") or
      String.starts_with?(s, "__mul_") or
      String.starts_with?(s, "__div_") or
      String.starts_with?(s, "__min_") or
      String.starts_with?(s, "__max_")
  end

  @doc "Returns a MapSet of internal variable names from a list of Variable structs."
  def internal_names(vars) when is_list(vars) do
    vars
    |> Enum.map(fn %__MODULE__{name: name} -> name end)
    |> Enum.filter(&internal?/1)
    |> MapSet.new()
  end

  @doc "Removes internal auxiliary variables from a values map."
  def filter_internal(values) when is_map(values) do
    Map.reject(values, fn {name, _} -> internal?(name) end)
  end

  @doc "Removes the given set of internal variable names from a values map."
  def reject_internal(values, internal_names) when is_map(values) do
    Map.reject(values, fn {name, _} -> MapSet.member?(internal_names, name) end)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{type: :bool, name: name}, _opts) do
      concat(["#Variable<bool ", Atom.to_string(name), ">"])
    end

    def inspect(
          %{type: :int, name: name, lower_bound: lower_bound, upper_bound: upper_bound},
          _opts
        ) do
      concat([
        "#Variable<int ",
        Atom.to_string(name),
        " ",
        Integer.to_string(lower_bound),
        "..",
        Integer.to_string(upper_bound),
        ">"
      ])
    end
  end
end
