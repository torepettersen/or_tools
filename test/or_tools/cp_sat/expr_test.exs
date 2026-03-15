defmodule OrTools.CpSat.ExprTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  describe "expr" do
    test "Enum.reduce with CpSat.expr() collects expressions at runtime" do
      terms =
        Enum.reduce([:x, :y, :z], CpSat.expr(), fn v, acc ->
          CpSat.expr(acc + 3 * v)
        end)

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :z], 0..10))
        |> CpSat.maximize(terms)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10, z: 10}, objective: 90.0}
    end

    test "for comprehension with into collects expressions" do
      terms =
        for v <- [:x, :y, :z], into: CpSat.expr() do
          CpSat.expr(v)
        end

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :z], 0..10))
        |> CpSat.maximize(terms)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10, z: 10}, objective: 30.0}
    end
  end

  describe "sum" do
    test "sum of atom list" do
      vars = [:a, :b, :c]

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c], 0..10))
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
        |> CpSat.add(CpSat.int_vars([:x, :y], 0..10))
        |> CpSat.constrain(sum(terms) <= 25)
        |> CpSat.maximize(sum(terms))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert 2 * result.values[:x] + 3 * result.values[:y] == 25
      assert result.objective == 25.0
    end

    test "sum of expr results can be added in maximize" do
      reward = Enum.map([:x, :y], fn v -> CpSat.expr(2 * v) end)
      penalty = [CpSat.expr(-1 * :z)]

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :z], 0..10))
        |> CpSat.maximize(sum(reward) + sum(penalty))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10, z: 0}, objective: 40.0}
    end
  end

  describe "abs" do
    test "maximize absolute value selects negative extreme" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, -10..5))
        |> CpSat.maximize(abs(:x))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: -10}, objective: 10.0}
    end

    test "maximize absolute value selects positive extreme" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, -5..10))
        |> CpSat.maximize(abs(:x))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 10.0}
    end

    test "expr builds abs terms for use in sum" do
      deviation = CpSat.expr(abs(:x - 5))

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.minimize(sum(deviation))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5}, objective: 0.0}
    end

    test "hidden abs variables are not in result" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.minimize(abs(:x - 3))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 3}, objective: 0.0}
    end

    test "runtime coefficient with abs" do
      penalty = 100

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.maximize(:x - penalty * abs(:x - 5))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5}, objective: 5.0}
    end
  end

  describe "mul" do
    test "variable multiplication in objective" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 0..10))
        |> CpSat.maximize(:x * :y)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10}, objective: 100.0}
    end
  end

  describe "div" do
    test "integer division in objective" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..100), CpSat.int_var(:y, 1..10)])
        |> CpSat.constrain(:x == 50)
        |> CpSat.constrain(:y == 7)
        |> CpSat.maximize(div(:x, :y))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 50, y: 7}, objective: 7.0}
    end
  end

  describe "min" do
    test "maximize the minimum (fairness)" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :z], 0..10))
        |> CpSat.constrain(:x + :y + :z == 15)
        |> CpSat.maximize(min([:x, :y, :z]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 5.0
    end

    test "hidden variables are not in result" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 0..10))
        |> CpSat.maximize(min([:x, :y]))
        |> CpSat.solve!()

      assert Map.keys(result.values) |> Enum.sort() == [:x, :y]
    end
  end

  describe "max" do
    test "minimize the maximum (balance)" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :z], 0..10))
        |> CpSat.constrain(:x + :y + :z == 15)
        |> CpSat.minimize(max([:x, :y, :z]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 5.0
    end

    test "hidden variables are not in result" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 0..10))
        |> CpSat.maximize(max([:x, :y]))
        |> CpSat.solve!()

      assert Map.keys(result.values) |> Enum.sort() == [:x, :y]
    end
  end

  describe "inspect" do
    test "simple variable" do
      assert inspect(CpSat.expr(:x)) == "#Expr<x>"
    end

    test "weighted variable" do
      assert inspect(CpSat.expr(3 * :x)) == "#Expr<3*x>"
    end

    test "multiple terms" do
      assert inspect(CpSat.expr(2 * :x + 3 * :y)) == "#Expr<2*x + 3*y>"
    end

    test "negative terms" do
      assert inspect(CpSat.expr(2 * :x - 3 * :y)) == "#Expr<2*x - 3*y>"
    end

    test "with constant offset" do
      assert inspect(CpSat.expr(:x + 5)) == "#Expr<x + 5>"
    end

    test "zero expression" do
      assert inspect(CpSat.expr()) == "#Expr<0>"
    end

    test "abs expression" do
      assert inspect(CpSat.expr(abs(:x))) == "#Expr<abs(...)>"
    end

    test "min expression" do
      assert inspect(CpSat.expr(min([:x, :y]))) == "#Expr<min(x, y)>"
    end

    test "max expression" do
      assert inspect(CpSat.expr(max([:x, :y]))) == "#Expr<max(x, y)>"
    end
  end
end
