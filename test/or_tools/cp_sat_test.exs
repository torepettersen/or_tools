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

    test "nonlinear variable multiplication" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.maximize(:x * :y)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10}, objective: 100.0}
    end

    test "integer division" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..100)
        |> CpSat.int_var(:y, 1..10)
        |> CpSat.constrain(:x == 50)
        |> CpSat.constrain(:y == 7)
        |> CpSat.maximize(div(:x, :y))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 50, y: 7}, objective: 7.0}
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

    test "sum of weighted expressions" do
      terms = [CpSat.expr(2 * :x), CpSat.expr(3 * :y)]

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

    test "sum of expr results" do
      expressions = Enum.map([:a, :b, :c], fn v -> CpSat.expr(2 * v) end)

      result =
        CpSat.new()
        |> CpSat.int_var(:a, 0..10)
        |> CpSat.int_var(:b, 0..10)
        |> CpSat.int_var(:c, 0..10)
        |> CpSat.constrain(sum(expressions) <= 30)
        |> CpSat.maximize(sum(expressions))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 30.0
    end

    test "sum of expr results can be added in maximize" do
      reward = Enum.map([:x, :y], fn v -> CpSat.expr(2 * v) end)
      penalty = [CpSat.expr(-1 * :z)]

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.int_var(:z, 0..10)
        |> CpSat.maximize(sum(reward) + sum(penalty))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10, z: 0}, objective: 40.0}
    end

    test "CpSat.sum/1 collects expr results at runtime" do
      expressions = Enum.map([:x, :y, :z], fn v -> CpSat.expr(3 * v) end)
      terms = CpSat.sum(expressions)

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.int_var(:z, 0..10)
        |> CpSat.maximize(terms)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10, z: 10}, objective: 90.0}
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

    test "runtime coefficient with abs" do
      penalty = 100

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(:x - penalty * abs(:x - 5))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5}, objective: 5.0}
    end

    test "negated runtime coefficient with abs" do
      penalty = 100

      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(:x + -penalty * abs(:x - 5))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5}, objective: 5.0}
    end
  end

  describe "pow" do
    test "maximize x squared" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(pow(:x, 2))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 100.0}
    end

    test "minimize x squared" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.minimize(pow(:x, 2))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 0}, objective: 0.0}
    end

    test "maximize x cubed" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..5)
        |> CpSat.maximize(pow(:x, 3))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5}, objective: 125.0}
    end

    test "coefficient with pow" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(3 * pow(:x, 2))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 300.0}
    end

    test "pow combined with linear terms" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(pow(:x, 2) + :x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 110.0}
    end

    test "hidden pow variables are not in result" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.maximize(pow(:x, 2))
        |> CpSat.solve!()

      assert Map.keys(result.values) == [:x]
    end
  end

  describe "min/max" do
    test "maximize the minimum (fairness)" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.int_var(:z, 0..10)
        |> CpSat.constrain(:x + :y + :z == 15)
        |> CpSat.maximize(min([:x, :y, :z]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 5.0
    end

    test "minimize the maximum (balance)" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.int_var(:z, 0..10)
        |> CpSat.constrain(:x + :y + :z == 15)
        |> CpSat.minimize(max([:x, :y, :z]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 5.0
    end

    test "max of variables" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..3)
        |> CpSat.int_var(:y, 0..7)
        |> CpSat.maximize(max([:x, :y]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 7.0
    end

    test "min of variables" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 3..10)
        |> CpSat.int_var(:y, 5..10)
        |> CpSat.minimize(min([:x, :y]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 3.0
    end

    test "hidden min/max variables are not in result" do
      result =
        CpSat.new()
        |> CpSat.int_var(:x, 0..10)
        |> CpSat.int_var(:y, 0..10)
        |> CpSat.maximize(min([:x, :y]))
        |> CpSat.solve!()

      assert Map.keys(result.values) |> Enum.sort() == [:x, :y]
    end
  end

  describe "boolean constraints" do
    test "exactly_one" do
      result =
        CpSat.new()
        |> CpSat.bool_var(:a)
        |> CpSat.bool_var(:b)
        |> CpSat.bool_var(:c)
        |> CpSat.exactly_one([:a, :b, :c])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "at_most_one" do
      result =
        CpSat.new()
        |> CpSat.bool_var(:a)
        |> CpSat.bool_var(:b)
        |> CpSat.bool_var(:c)
        |> CpSat.at_most_one([:a, :b, :c])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "at_most_one allows zero" do
      result =
        CpSat.new()
        |> CpSat.bool_var(:a)
        |> CpSat.bool_var(:b)
        |> CpSat.at_most_one([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 0, b: 0}, objective: 0.0}
    end

    test "at_least_one" do
      result =
        CpSat.new()
        |> CpSat.bool_var(:a)
        |> CpSat.bool_var(:b)
        |> CpSat.bool_var(:c)
        |> CpSat.at_least_one([:a, :b, :c])
        |> CpSat.minimize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "bool_and forces all true" do
      result =
        CpSat.new()
        |> CpSat.bool_var(:a)
        |> CpSat.bool_var(:b)
        |> CpSat.bool_and([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 1, b: 1}, objective: 2.0}
    end

    test "bool_or allows any true" do
      result =
        CpSat.new()
        |> CpSat.bool_var(:a)
        |> CpSat.bool_var(:b)
        |> CpSat.bool_or([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "bool_xor requires odd number true" do
      result =
        CpSat.new()
        |> CpSat.bool_var(:a)
        |> CpSat.bool_var(:b)
        |> CpSat.bool_xor([:a, :b])
        |> CpSat.maximize(:a + :b)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
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
