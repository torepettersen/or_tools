defmodule OrTools.CpSat.Variable do
  @moduledoc false

  defstruct [:type, :name, :lb, :ub]

  @type t :: %__MODULE__{
          type: :bool | :int,
          name: atom(),
          lb: integer() | nil,
          ub: integer() | nil
        }

  @doc false
  def to_tuple(%__MODULE__{type: :bool, name: name}), do: {name, 0, 1}
  def to_tuple(%__MODULE__{type: :int, name: name, lb: lb, ub: ub}), do: {name, lb, ub}

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{type: :bool, name: name}, _opts) do
      concat(["#Variable<bool ", Atom.to_string(name), ">"])
    end

    def inspect(%{type: :int, name: name, lb: lb, ub: ub}, _opts) do
      concat(["#Variable<int ", Atom.to_string(name), " ", Integer.to_string(lb), "..", Integer.to_string(ub), ">"])
    end
  end
end
