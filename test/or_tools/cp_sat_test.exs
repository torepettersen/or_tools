defmodule OrTools.CpSatTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  describe "basic solving" do
    test "solves a simple maximization" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.maximize(:x + :y)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10}, objective: 20.0}
    end

    test "solves a simple minimization" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.minimize(:x + :y)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 0, y: 0}, objective: 0.0}
    end

    test "returns infeasible for contradictory constraints" do
      {:ok, result} =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.constrain(:x >= 5)
        |> CpSat.constrain(:x <= 3)
        |> CpSat.maximize(:x)
        |> CpSat.solve()

      assert result.status == :infeasible
    end
  end

  describe "constraints" do
    test "less than or equal" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..100)
        |> CpSat.constrain(:x <= 7)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7}, objective: 7.0}
    end

    test "greater than or equal" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..100)
        |> CpSat.constrain(:x >= 42)
        |> CpSat.minimize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 42}, objective: 42.0}
    end

    test "equality" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..100)
        |> CpSat.constrain(:x == 25)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 25}, objective: 25.0}
    end

    test "not equal" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..2)
        |> CpSat.constrain(:x != 0)
        |> CpSat.minimize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 1}, objective: 1.0}
    end

    test "weighted linear constraint" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..50)
        |> CpSat.int_var(:y, 0..50)
        |> CpSat.int_var(:z, 0..50)
        |> CpSat.constrain(2 * :x + 7 * :y + 3 * :z <= 50)
        |> CpSat.constrain(3 * :x - 5 * :y + 7 * :z <= 45)
        |> CpSat.constrain(5 * :x + 2 * :y - 6 * :z <= 37)
        |> CpSat.maximize(2 * :x + 2 * :y + 3 * :z)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7, y: 3, z: 5}, objective: 35.0}
    end

    test "all_different" do
      result =
        CpSat.new()
        |> CpSat.int_var(:a, 1..3)
        |> CpSat.int_var(:b, 1..3)
        |> CpSat.int_var(:c, 1..3)
        |> CpSat.all_different([:a, :b, :c])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values |> Map.values() |> Enum.sort() == [1, 2, 3]
    end
  end

  describe "runtime variables" do
    test "atom variable bound at runtime" do
      x = :x
      y = :y

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.constrain(x + y <= 15)
        |> CpSat.maximize(x + y)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values[:x] + result.values[:y] == 15
      assert result.objective == 15.0
    end

    test "runtime integer on the right side of constraint" do
      limit = 7

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..100)
        |> CpSat.constrain(:x <= limit)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7}, objective: 7.0}
    end

    test "runtime coefficient in multiplication" do
      coeff = 3

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.constrain(coeff * :x <= 21)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7}, objective: 7.0}
    end
  end

  describe "bool_var" do
    test "creates a 0..1 variable" do
      result =
        CpSat.new()
        |> CpSat.bool_var(:flag)
        |> CpSat.maximize(:flag)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{flag: 1}, objective: 1.0}
    end
  end

  describe "sum" do
    test "sum of atom list" do
      vars = [:a, :b, :c]

      result =
        CpSat.new()
        |> CpSat.int_var(:a, 0..10)
        |> CpSat.int_var(:b, 0..10)
        |> CpSat.int_var(:c, 0..10)
        |> CpSat.constrain(sum(vars) <= 20)
        |> CpSat.maximize(sum(vars))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values[:a] + result.values[:b] + result.values[:c] == 20
      assert result.objective == 20.0
    end

    test "sum of weighted tuples" do
      terms = [{:x, 2}, {:y, 3}]

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.constrain(sum(terms) <= 25)
        |> CpSat.maximize(sum(terms))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert 2 * result.values[:x] + 3 * result.values[:y] == 25
      assert result.objective == 25.0
    end
  end

  describe "abs" do
    test "maximize absolute value" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, -5..10)
        |> CpSat.maximize(abs(:x))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 10.0}
    end

    test "maximize absolute value with negative range" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, -10..5)
        |> CpSat.maximize(abs(:x))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: -10}, objective: 10.0}
    end

    test "maximize with abs penalty" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(10 * :x - abs(:x - 5))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 95.0}
    end

    test "strong abs penalty pushes toward target" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(:x - 100 * abs(:x - 5))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5}, objective: 5.0}
    end

    test "expr builds abs terms for use in sum" do
      deviation = CpSat.expr(abs(:x - 5))

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.maximize(:x + :y - 3 * sum(deviation))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5, y: 10}, objective: 15.0}
    end

    test "hidden abs variables are not in result" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.minimize(abs(:x - 3))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 3}, objective: 0.0}
    end
  end

  describe "validation" do
    test "solve! raises on unknown variable in constraint" do
      assert_raise ArgumentError, ~r/unknown variable/, fn ->
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.constrain(:x + :y <= 10)
        |> CpSat.solve!()
      end
    end

    test "solve! raises on unknown variable in objective" do
      assert_raise ArgumentError, ~r/unknown variable/, fn ->
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(:x + :missing)
        |> CpSat.solve!()
      end
    end

    test "validate returns error tuple" do
      {:error, message} =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.constrain(:x + :nope <= 5)
        |> CpSat.validate()

      assert message =~ "unknown variable"
      assert message =~ "nope"
    end
  end
end
