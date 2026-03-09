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
  def bool(name) when is_atom(name), do: %__MODULE__{type: :bool, name: name}

  @doc false
  def int(name, %Range{first: lower_bound, last: upper_bound}) when is_atom(name) do
    int(name, lower_bound, upper_bound)
  end

  def int(name, lower_bound, upper_bound)
      when is_atom(name) and is_integer(lower_bound) and is_integer(upper_bound) do
    %__MODULE__{type: :int, name: name, lower_bound: lower_bound, upper_bound: upper_bound}
  end

  @doc false
  def to_tuple(%__MODULE__{type: :bool, name: name}), do: {name, 0, 1}

  def to_tuple(%__MODULE__{
        type: :int,
        name: name,
        lower_bound: lower_bound,
        upper_bound: upper_bound
      }),
      do: {name, lower_bound, upper_bound}

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
