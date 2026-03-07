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
  def to_tuple(%__MODULE__{type: :bool, name: name}), do: {name, 0, 1}

  def to_tuple(%__MODULE__{type: :int, name: name, lower_bound: lower_bound, upper_bound: upper_bound}),
    do: {name, lower_bound, upper_bound}

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{type: :bool, name: name}, _opts) do
      concat(["#Variable<bool ", Atom.to_string(name), ">"])
    end

    def inspect(%{type: :int, name: name, lower_bound: lower_bound, upper_bound: upper_bound}, _opts) do
      concat(["#Variable<int ", Atom.to_string(name), " ", Integer.to_string(lower_bound), "..", Integer.to_string(upper_bound), ">"])
    end
  end
end
