defmodule OrTools.CpSat.VariableTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  alias OrTools.CpSat.Variable

  describe "Variable.bool/1" do
    test "creates a bool variable struct" do
      var = Variable.bool(:flag)
      assert var.type == :bool
      assert var.name == :flag
    end

    test "to_tuple returns 0..1 bounds" do
      assert Variable.to_tuple(Variable.bool(:flag)) == {:flag, 0, 1}
    end

    test "inspect" do
      assert inspect(Variable.bool(:flag)) == "#Variable<bool flag>"
    end

    test "creates a 0..1 variable that solves correctly" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_var(:flag))
        |> CpSat.maximize(:flag)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{flag: 1}, objective: 1.0}
    end
  end

  describe "Variable.int/2 and /3" do
    test "creates an int variable with range" do
      var = Variable.int(:x, 0..10)
      assert var.type == :int
      assert var.name == :x
      assert var.lower_bound == 0
      assert var.upper_bound == 10
    end

    test "creates an int variable with explicit bounds" do
      var = Variable.int(:x, 0, 10)
      assert var.type == :int
      assert var.name == :x
      assert var.lower_bound == 0
      assert var.upper_bound == 10
    end

    test "to_tuple returns name, lower, upper" do
      assert Variable.to_tuple(Variable.int(:x, 3, 7)) == {:x, 3, 7}
    end

    test "inspect" do
      assert inspect(Variable.int(:x, 0, 10)) == "#Variable<int x 0..10>"
    end
  end

  describe "Variable struct in model" do
    test "int_var returns {model, var} when model is first arg" do
      {model, var} = CpSat.int_var(CpSat.new(), :x, 0, 10)

      assert var.name == :x
      assert var.lower_bound == 0
      assert var.upper_bound == 10
      assert length(model.vars) == 1
    end

    test "Variable struct can be used directly in expressions" do
      x_var = CpSat.int_var(:x, 0..10)
      y_var = CpSat.int_var(:y, 0..10)

      result =
        CpSat.new()
        |> CpSat.add([x_var, y_var])
        |> CpSat.constrain(x_var + y_var <= 15)
        |> CpSat.maximize(x_var + y_var)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values.x + result.values.y == 15
    end

    test "value/2 reads result by Variable struct" do
      x_var = CpSat.int_var(:x, 0..10)

      result =
        CpSat.new()
        |> CpSat.add(x_var)
        |> CpSat.constrain(x_var == 7)
        |> CpSat.maximize(x_var)
        |> CpSat.solve!()

      assert CpSat.value(result, x_var) == 7
    end

    test "interval_var with integer duration solves correctly" do
      start_var = CpSat.int_var(:s, 0, 20)
      end_var = CpSat.int_var(:e, 0, 20)

      result =
        CpSat.new()
        |> CpSat.add([start_var, end_var])
        |> CpSat.add(CpSat.interval_var(start_var, :task, 5, end_var))
        |> CpSat.constrain(start_var >= 3)
        |> CpSat.minimize(start_var)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values.s == 3
      assert result.values.e == 8
    end
  end
end
