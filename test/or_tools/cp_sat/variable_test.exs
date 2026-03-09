defmodule OrTools.CpSat.VariableTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  alias OrTools.CpSat.Variable

  describe "Variable.bool/1" do
    test "reaches upper bound (1) when maximized" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_var(:flag))
        |> CpSat.maximize(:flag)
        |> CpSat.solve!()

      assert result.values.flag == 1
    end

    test "reaches lower bound (0) when minimized" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_var(:flag))
        |> CpSat.minimize(:flag)
        |> CpSat.solve!()

      assert result.values.flag == 0
    end

    test "inspect" do
      assert inspect(Variable.bool(:flag)) == "#Variable<bool flag>"
    end
  end

  describe "Variable.int/2" do
    test "reaches upper bound when maximized" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 3..7))
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result.values.x == 7
    end

    test "reaches lower bound when minimized" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 3..7))
        |> CpSat.minimize(:x)
        |> CpSat.solve!()

      assert result.values.x == 3
    end

    test "inspect" do
      assert inspect(Variable.int(:x, 0, 10)) == "#Variable<int x 0..10>"
    end
  end

  describe "Variable struct in model" do
    test "can be used directly in expressions" do
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

    test "interval_var with fixed duration enforces start + duration = end" do
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
