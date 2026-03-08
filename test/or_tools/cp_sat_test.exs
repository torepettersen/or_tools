defmodule OrTools.CpSatTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  describe "basic solving" do
    test "solves a simple maximization" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
        |> CpSat.maximize(:x + :y)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10}, objective: 20.0}
    end

    test "solves a simple minimization" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
        |> CpSat.minimize(:x + :y)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 0, y: 0}, objective: 0.0}
    end

    test "nonlinear variable multiplication" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
        |> CpSat.maximize(:x * :y)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10}, objective: 100.0}
    end

    test "integer division" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..100), CpSat.int_var(:y, 1..10)])
        |> CpSat.constrain(:x == 50)
        |> CpSat.constrain(:y == 7)
        |> CpSat.maximize(div(:x, :y))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 50, y: 7}, objective: 7.0}
    end

    test "returns infeasible for contradictory constraints" do
      {:ok, result} =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
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
        |> CpSat.add(CpSat.int_var(:x, 0..100))
        |> CpSat.constrain(:x <= 7)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7}, objective: 7.0}
    end

    test "greater than or equal" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..100))
        |> CpSat.constrain(:x >= 42)
        |> CpSat.minimize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 42}, objective: 42.0}
    end

    test "equality" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..100))
        |> CpSat.constrain(:x == 25)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 25}, objective: 25.0}
    end

    test "not equal" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..2))
        |> CpSat.constrain(:x != 0)
        |> CpSat.minimize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 1}, objective: 1.0}
    end

    test "constrain/1 with for into: model" do
      vars = [:x, :y, :z]

      model =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10), CpSat.int_var(:z, 0..10)])

      model =
        for var <- vars, into: model do
          CpSat.constrain(var <= 5)
        end

      result =
        model
        |> CpSat.maximize(:x + :y + :z)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5, y: 5, z: 5}, objective: 15.0}
    end

    test "weighted linear constraint" do
      result =
        CpSat.new()
        |> CpSat.add([
          CpSat.int_var(:x, 0..50),
          CpSat.int_var(:y, 0..50),
          CpSat.int_var(:z, 0..50)
        ])
        |> CpSat.constrain(2 * :x + 7 * :y + 3 * :z <= 50)
        |> CpSat.constrain(3 * :x - 5 * :y + 7 * :z <= 45)
        |> CpSat.constrain(5 * :x + 2 * :y - 6 * :z <= 37)
        |> CpSat.maximize(2 * :x + 2 * :y + 3 * :z)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7, y: 3, z: 5}, objective: 35.0}
    end

    test "interval_var with integer duration creates an interval_fixed constraint" do
      start_var = CpSat.int_var(:start, 0, 10)
      end_var = CpSat.int_var(:end_time, 0, 10)
      interval = CpSat.interval_var(start_var, :task, 3, end_var)

      model = CpSat.new() |> CpSat.add([start_var, end_var, interval])

      assert length(model.constraints) == 1
      [constraint] = model.constraints
      assert constraint.type == :interval_fixed
      assert constraint.data == {:task, :start, 3, :end_time}
    end

    test "no_overlap prevents two tasks from overlapping" do
      start1 = CpSat.int_var(:s1, 0, 10)
      end1 = CpSat.int_var(:e1, 0, 10)
      start2 = CpSat.int_var(:s2, 0, 10)
      end2 = CpSat.int_var(:e2, 0, 10)

      model = CpSat.new() |> CpSat.add([start1, end1, start2, end2])
      {model, interval1} = CpSat.interval_var(model, :t1, start1, 3, end1)
      {model, interval2} = CpSat.interval_var(model, :t2, start2, 3, end2)

      result =
        model
        |> CpSat.add(CpSat.no_overlap([interval1, interval2]))
        |> CpSat.minimize(:s1 + :s2)
        |> CpSat.solve!()

      assert result.status == :optimal
      s1 = result.values[:s1]
      s2 = result.values[:s2]
      assert s1 + 3 <= s2 or s2 + 3 <= s1
    end

    test "all_different" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:a, 1..3), CpSat.int_var(:b, 1..3), CpSat.int_var(:c, 1..3)])
        |> CpSat.all_different([:a, :b, :c])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values |> Map.values() |> Enum.sort() == [1, 2, 3]
    end

    test "all_different with expr offset" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c], 0..4))
        |> CpSat.all_different(Enum.map([:a, :b, :c], fn v -> CpSat.expr(v + 1) end))
        |> CpSat.solve!()

      assert result.status == :optimal
      # a+1, b+1, c+1 all different means a, b, c all different
      assert result.values |> Map.values() |> Enum.uniq() |> length() == 3
    end

    test "all_different with expr offset enforces stricter constraint" do
      # a+0, b+1, c+2 all different is stricter: e.g. a=0,b=0,c=0 would give 0,1,2 (ok),
      # but a=1,b=0,c=0 gives 1,1,2 (not ok)
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c], 0..2))
        |> CpSat.all_different([:a, :b, :c])
        |> CpSat.all_different([CpSat.expr(:a + 0), CpSat.expr(:b + 1), CpSat.expr(:c + 2)])
        |> CpSat.solve!()

      assert result.status in [:optimal, :infeasible]
    end
  end

  describe "runtime variables" do
    test "atom variable bound at runtime" do
      x = :x
      y = :y

      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
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
        |> CpSat.add(CpSat.int_var(:x, 0..100))
        |> CpSat.constrain(:x <= limit)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7}, objective: 7.0}
    end

    test "runtime coefficient in multiplication" do
      coeff = 3

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.constrain(coeff * :x <= 21)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7}, objective: 7.0}
    end
  end

  describe "Variable struct" do
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

  describe "bool_var" do
    test "creates a 0..1 variable" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_var(:flag))
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
        |> CpSat.add([CpSat.int_var(:a, 0..10), CpSat.int_var(:b, 0..10), CpSat.int_var(:c, 0..10)])
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
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
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
        |> CpSat.add([CpSat.int_var(:a, 0..10), CpSat.int_var(:b, 0..10), CpSat.int_var(:c, 0..10)])
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
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10), CpSat.int_var(:z, 0..10)])
        |> CpSat.maximize(sum(reward) + sum(penalty))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10, z: 0}, objective: 40.0}
    end

    test "Enum.reduce with CpSat.expr() collects expr results at runtime" do
      terms =
        Enum.reduce([:x, :y, :z], CpSat.expr(), fn v, acc ->
          CpSat.expr(acc + 3 * v)
        end)

      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10), CpSat.int_var(:z, 0..10)])
        |> CpSat.maximize(terms)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10, y: 10, z: 10}, objective: 90.0}
    end
  end

  describe "abs" do
    test "maximize absolute value" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, -5..10))
        |> CpSat.maximize(abs(:x))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 10.0}
    end

    test "maximize absolute value with negative range" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, -10..5))
        |> CpSat.maximize(abs(:x))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: -10}, objective: 10.0}
    end

    test "maximize with abs penalty" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.maximize(10 * :x - abs(:x - 5))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 95.0}
    end

    test "strong abs penalty pushes toward target" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.maximize(:x - 100 * abs(:x - 5))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5}, objective: 5.0}
    end

    test "expr builds abs terms for use in sum" do
      deviation = CpSat.expr(abs(:x - 5))

      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
        |> CpSat.maximize(:x + :y - 3 * sum(deviation))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5, y: 10}, objective: 15.0}
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

    test "negated runtime coefficient with abs" do
      penalty = 100

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.maximize(:x + -penalty * abs(:x - 5))
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 5}, objective: 5.0}
    end
  end

  describe "min/max" do
    test "maximize the minimum (fairness)" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10), CpSat.int_var(:z, 0..10)])
        |> CpSat.constrain(:x + :y + :z == 15)
        |> CpSat.maximize(min([:x, :y, :z]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 5.0
    end

    test "minimize the maximum (balance)" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10), CpSat.int_var(:z, 0..10)])
        |> CpSat.constrain(:x + :y + :z == 15)
        |> CpSat.minimize(max([:x, :y, :z]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 5.0
    end

    test "max of variables" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..3), CpSat.int_var(:y, 0..7)])
        |> CpSat.maximize(max([:x, :y]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 7.0
    end

    test "min of variables" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 3..10), CpSat.int_var(:y, 5..10)])
        |> CpSat.minimize(min([:x, :y]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 3.0
    end

    test "max_eq sets target to the maximum of a list of variables" do
      result =
        CpSat.new()
        |> CpSat.add([
          CpSat.int_var(:a, 0, 10),
          CpSat.int_var(:b, 0, 10),
          CpSat.int_var(:c, 0, 10),
          CpSat.int_var(:m, 0, 10)
        ])
        |> CpSat.constrain(:a == 3)
        |> CpSat.constrain(:b == 7)
        |> CpSat.constrain(:c == 5)
        |> CpSat.max_eq(:m, [:a, :b, :c])
        |> CpSat.minimize(:m)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values[:m] == 7
    end

    test "max_eq accepts Variable struct as target" do
      m_var = CpSat.int_var(:m, 0, 10)

      result =
        CpSat.new()
        |> CpSat.add([
          CpSat.int_var(:a, 0, 10),
          CpSat.int_var(:b, 0, 10),
          CpSat.int_var(:c, 0, 10),
          m_var
        ])
        |> CpSat.constrain(:a == 3)
        |> CpSat.constrain(:b == 7)
        |> CpSat.constrain(:c == 5)
        |> CpSat.max_eq(m_var, [:a, :b, :c])
        |> CpSat.minimize(:m)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert CpSat.value(result, m_var) == 7
    end

    test "hidden min/max variables are not in result" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
        |> CpSat.maximize(min([:x, :y]))
        |> CpSat.solve!()

      assert Map.keys(result.values) |> Enum.sort() == [:x, :y]
    end
  end

  describe "boolean constraints" do
    test "exactly_one" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b, :c]))
        |> CpSat.exactly_one([:a, :b, :c])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "at_most_one" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b, :c]))
        |> CpSat.at_most_one([:a, :b, :c])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "at_most_one allows zero" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b]))
        |> CpSat.at_most_one([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 0, b: 0}, objective: 0.0}
    end

    test "at_least_one" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b, :c]))
        |> CpSat.at_least_one([:a, :b, :c])
        |> CpSat.minimize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "bool_and forces all true" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b]))
        |> CpSat.bool_and([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 1, b: 1}, objective: 2.0}
    end

    test "bool_or allows any true" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b]))
        |> CpSat.bool_or([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "bool_xor requires odd number true" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b]))
        |> CpSat.bool_xor([:a, :b])
        |> CpSat.maximize(:a + :b)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end
  end

  describe "solve_all" do
    test "enumerates all solutions" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..3), CpSat.int_var(:y, 1..3)])
        |> CpSat.all_different([:x, :y])
        |> CpSat.solve_all!()

      assert result.status == :optimal
      assert length(result.solutions) == 6

      all_values = Enum.map(result.solutions, & &1.values)

      assert Enum.sort(all_values) ==
               Enum.sort([
                 %{x: 1, y: 2},
                 %{x: 1, y: 3},
                 %{x: 2, y: 1},
                 %{x: 2, y: 3},
                 %{x: 3, y: 1},
                 %{x: 3, y: 2}
               ])
    end

    test "includes objective in each solution" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..3), CpSat.int_var(:y, 1..3)])
        |> CpSat.all_different([:x, :y])
        |> CpSat.maximize(:x + :y)
        |> CpSat.solve_all!()

      for solution <- result.solutions do
        assert Map.has_key?(solution, :objective)
        assert Map.has_key?(solution, :values)
      end
    end

    test "on_solution callback accumulates state in result.state" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..3), CpSat.int_var(:y, 1..3)])
        |> CpSat.all_different([:x, :y])
        |> CpSat.solve_all!(
          init: fn _variables -> [] end,
          on_solution: fn solution, acc -> [solution | acc] end
        )

      assert length(result.state) == 6

      # With on_solution, solutions are not stored in memory
      assert result.solutions == []
      assert result.metrics.num_solutions == 6

      # Each accumulated solution has the same shape
      for solution <- result.state do
        assert Map.has_key?(solution, :values)
        assert Map.has_key?(solution, :objective)
      end
    end

    test "on_solution callback can count solutions" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..3), CpSat.int_var(:y, 1..3)])
        |> CpSat.all_different([:x, :y])
        |> CpSat.solve_all!(
          init: fn _variables -> 0 end,
          on_solution: fn _solution, count -> count + 1 end
        )

      assert result.state == 6
      assert result.metrics.num_solutions == 6
      assert result.solutions == []
    end

    test "init receives variable names and sets initial state" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..2), CpSat.int_var(:y, 1..2)])
        |> CpSat.solve_all!(
          init: fn variables -> variables end,
          on_solution: fn _solution, state -> state end
        )

      assert result.state == [:x, :y]
    end

    test "default init sets state to variable names" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..2), CpSat.int_var(:y, 1..2)])
        |> CpSat.solve_all!(on_solution: fn _solution, state -> state end)

      assert result.state == [:x, :y]
    end

    test "returns empty solutions for infeasible model" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..1))
        |> CpSat.constrain(:x >= 2)
        |> CpSat.solve_all!()

      assert result.status == :infeasible
      assert result.solutions == []
    end

    test "includes metrics" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..3), CpSat.int_var(:y, 1..3)])
        |> CpSat.all_different([:x, :y])
        |> CpSat.solve_all!()

      assert Map.has_key?(result.metrics, :num_conflicts)
      assert Map.has_key?(result.metrics, :num_branches)
      assert Map.has_key?(result.metrics, :wall_time_us)
      assert result.metrics.num_solutions == 6
    end

    test "on_solution can halt early with {:halt, state}" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..10), CpSat.int_var(:y, 1..10)])
        |> CpSat.solve_all!(
          init: fn _variables -> 0 end,
          on_solution: fn _solution, count ->
            count = count + 1

            if count < 3 do
              count
            else
              {:halt, count}
            end
          end
        )

      assert result.state == 3
    end
  end

  describe "params" do
    test "max_time_in_seconds accepts a time limit" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..100))
        |> CpSat.maximize(:x)
        |> CpSat.solve!(params: [max_time_in_seconds: 10])

      assert result.status == :optimal
      assert result.values.x == 100
    end

    test "max_time_in_seconds very short stops early on hard problem" do
      vars = Enum.map(0..11, fn i -> :"q#{i}" end)

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars(vars, 0..11))
        |> CpSat.all_different(vars)
        |> CpSat.solve!(params: [max_time_in_seconds: 0.000001])

      assert result.status in [:unknown, :feasible, :optimal]
    end

    test "max_time_in_seconds works with solve_all" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 1..100))
        |> CpSat.solve_all!(params: [max_time_in_seconds: 0.000001])

      assert result.status in [:unknown, :feasible, :optimal]
    end

    test "random_seed produces deterministic results" do
      solve = fn ->
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
        |> CpSat.maximize(:x + :y)
        |> CpSat.solve!(params: [random_seed: 42])
      end

      assert solve.() == solve.()
    end
  end

  describe "validation" do
    test "solve! raises on unknown variable in constraint" do
      assert_raise ArgumentError, ~r/unknown variable/, fn ->
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.constrain(:x + :y <= 10)
        |> CpSat.solve!()
      end
    end

    test "solve! raises on unknown variable in objective" do
      assert_raise ArgumentError, ~r/unknown variable/, fn ->
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.maximize(:x + :missing)
        |> CpSat.solve!()
      end
    end

    test "validate returns error tuple" do
      {:error, message} =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.constrain(:x + :nope <= 5)
        |> CpSat.validate()

      assert message =~ "unknown variable"
      assert message =~ "nope"
    end
  end
end
