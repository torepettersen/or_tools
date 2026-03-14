defmodule OrTools.CpSat.Variable do
  @moduledoc false

  defstruct [:type, :name, :lower_bound, :upper_bound, :start_name, :duration, :end_name]

  @type t :: %__MODULE__{
          type: :bool | :int | :interval,
          name: atom(),
          lower_bound: integer() | nil,
          upper_bound: integer() | nil,
          start_name: atom() | nil,
          duration: atom() | integer() | nil,
          end_name: atom() | nil
        }

  def bool_var(name) when is_atom(name) do
    %__MODULE__{type: :bool, name: name}
  end

  def bool_vars(names) when is_list(names) do
    Enum.map(names, &bool_var/1)
  end

  def int_var(name, %Range{first: lower_bound, last: upper_bound}) when is_atom(name) do
    int_var(name, lower_bound, upper_bound)
  end

  def int_var(name, lower_bound, upper_bound)
      when is_atom(name) and is_integer(lower_bound) and is_integer(upper_bound) do
    %__MODULE__{type: :int, name: name, lower_bound: lower_bound, upper_bound: upper_bound}
  end

  def int_vars(names, %Range{} = range) when is_list(names) do
    Enum.map(names, &int_var(&1, range))
  end

  def interval_var(name, %__MODULE__{name: start_name}, duration, %__MODULE__{name: end_name})
      when is_atom(name) and is_integer(duration) do
    interval_var(name, start_name, duration, end_name)
  end

  def interval_var(name, start_name, duration, end_name)
      when is_atom(name) and is_atom(start_name) and
             (is_atom(duration) or is_integer(duration)) and is_atom(end_name) do
    %__MODULE__{
      type: :interval,
      name: name,
      start_name: start_name,
      duration: duration,
      end_name: end_name
    }
  end

  def resolve_names(items) when is_list(items) do
    Enum.map(items, fn
      %__MODULE__{name: name} -> name
      name when is_atom(name) -> name
    end)
  end

  def to_tuple(%__MODULE__{type: :bool, name: name}) do
    {name, 0, 1}
  end

  def to_tuple(%__MODULE__{
        type: :int,
        name: name,
        lower_bound: lower_bound,
        upper_bound: upper_bound
      }) do
    {name, lower_bound, upper_bound}
  end

  def to_tuple(%__MODULE__{
        type: :interval,
        name: name,
        start_name: start_name,
        duration: duration,
        end_name: end_name
      })
      when is_atom(duration) do
    {:interval, name, start_name, duration, end_name}
  end

  def to_tuple(%__MODULE__{
        type: :interval,
        name: name,
        start_name: start_name,
        duration: duration,
        end_name: end_name
      })
      when is_integer(duration) do
    {:interval_fixed, name, start_name, duration, end_name}
  end

  def validate_all([], _declared), do: :ok

  def validate_all([var | rest], declared) do
    case validate(var, declared) do
      :ok -> validate_all(rest, declared)
      error -> error
    end
  end

  def validate(
        %__MODULE__{
          type: :interval,
          start_name: start_name,
          duration: duration,
          end_name: end_name
        },
        declared
      )
      when is_atom(duration) do
    check_names([start_name, duration, end_name], declared)
  end

  def validate(%__MODULE__{type: :interval, start_name: start_name, end_name: end_name}, declared) do
    check_names([start_name, end_name], declared)
  end

  defp check_names(names, declared) do
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

  def bounds_map(vars) when is_list(vars) do
    Map.new(vars, fn %__MODULE__{name: name, lower_bound: lower_bound, upper_bound: upper_bound} ->
      {name, {lower_bound || 0, upper_bound || 1}}
    end)
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

    def inspect(
          %{
            type: :interval,
            name: name,
            start_name: start_name,
            duration: duration,
            end_name: end_name
          },
          _opts
        )
        when is_atom(duration) do
      concat([
        "#Variable<interval ",
        Atom.to_string(name),
        "(",
        Atom.to_string(start_name),
        ", ",
        Atom.to_string(duration),
        ", ",
        Atom.to_string(end_name),
        ")>"
      ])
    end

    def inspect(
          %{
            type: :interval,
            name: name,
            start_name: start_name,
            duration: duration,
            end_name: end_name
          },
          _opts
        )
        when is_integer(duration) do
      concat([
        "#Variable<interval ",
        Atom.to_string(name),
        "(",
        Atom.to_string(start_name),
        ", fixed:",
        Integer.to_string(duration),
        ", ",
        Atom.to_string(end_name),
        ")>"
      ])
    end
  end
end
