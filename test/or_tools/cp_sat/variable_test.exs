defmodule OrTools.CpSat.VariableTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  alias OrTools.CpSat.Variable

  describe "bool_var/1" do
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
      assert inspect(Variable.bool_var(:flag)) == "#Variable<bool flag>"
    end
  end

  describe "int_var/2" do
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
      assert inspect(Variable.int_var(:x, 0, 10)) == "#Variable<int x 0..10>"
    end
  end

  describe "interval_var/4" do
    test "start reaches upper bound when maximized" do
      start_var = CpSat.int_var(:s, 0, 20)
      end_var = CpSat.int_var(:e, 0, 20)

      result =
        CpSat.new()
        |> CpSat.add([start_var, end_var])
        |> CpSat.add(CpSat.interval_var(:task, start_var, 5, end_var))
        |> CpSat.constrain(start_var <= 10)
        |> CpSat.maximize(start_var)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values.s == 10
      assert result.values.e == 15
    end

    test "start reaches lower bound when minimized" do
      start_var = CpSat.int_var(:s, 0, 20)
      end_var = CpSat.int_var(:e, 0, 20)

      result =
        CpSat.new()
        |> CpSat.add([start_var, end_var])
        |> CpSat.add(CpSat.interval_var(:task, start_var, 5, end_var))
        |> CpSat.constrain(start_var >= 3)
        |> CpSat.minimize(start_var)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values.s == 3
      assert result.values.e == 8
    end

    test "variable duration enforces start + duration = end" do
      start_var = CpSat.int_var(:s, 0, 20)
      duration_var = CpSat.int_var(:d, 1, 10)
      end_var = CpSat.int_var(:e, 0, 20)

      result =
        CpSat.new()
        |> CpSat.add([start_var, duration_var, end_var])
        |> CpSat.add(CpSat.interval_var(:task, start_var, duration_var, end_var))
        |> CpSat.constrain(start_var == 3)
        |> CpSat.constrain(duration_var == 6)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values.s == 3
      assert result.values.d == 6
      assert result.values.e == 9
    end

    test "inspect with fixed duration" do
      start_var = CpSat.int_var(:s, 0, 20)
      end_var = CpSat.int_var(:e, 0, 20)

      assert inspect(CpSat.interval_var(:task, start_var, 5, end_var)) ==
               "#Variable<interval task(s, fixed:5, e)>"
    end

    test "inspect with variable duration" do
      start_var = CpSat.int_var(:s, 0, 20)
      duration_var = CpSat.int_var(:d, 1, 10)
      end_var = CpSat.int_var(:e, 0, 20)

      assert inspect(CpSat.interval_var(:task, start_var, duration_var, end_var)) ==
               "#Variable<interval task(s, d, e)>"
    end
  end
end
