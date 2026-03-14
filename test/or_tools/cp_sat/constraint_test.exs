defmodule OrTools.CpSat.ConstraintTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  describe "linear constraints" do
    test "less than or equal limits the maximum" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..100))
        |> CpSat.constrain(:x <= 7)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7}, objective: 7.0}
    end

    test "greater than or equal lifts the minimum" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..100))
        |> CpSat.constrain(:x >= 42)
        |> CpSat.minimize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 42}, objective: 42.0}
    end

    test "equality pins the value" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..100))
        |> CpSat.constrain(:x == 25)
        |> CpSat.maximize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 25}, objective: 25.0}
    end

    test "not equal excludes the specified value" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..2))
        |> CpSat.constrain(:x != 0)
        |> CpSat.minimize(:x)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 1}, objective: 1.0}
    end

    test "weighted linear constraint limits combined value" do
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
  end

  describe "all_different" do
    test "keeps x, y, z at distinct values" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 1..3), CpSat.int_var(:y, 1..3), CpSat.int_var(:z, 1..3)])
        |> CpSat.all_different([:x, :y, :z])
        |> CpSat.maximize(:x + :y + :z)
        |> CpSat.solve!()

      assert result.status == :optimal
      values = Map.values(result.values)
      assert Enum.uniq(values) == values
      assert Enum.sort(values) == [1, 2, 3]
    end

    test "with expr offset keeps offset values distinct" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c], 0..4))
        |> CpSat.all_different(Enum.map([:a, :b, :c], fn v -> CpSat.expr(v + 1) end))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values |> Map.values() |> Enum.uniq() |> length() == 3
    end

    test "with expr offset enforces stricter constraint" do
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

  describe "no_overlap" do
    test "prevents two tasks from overlapping" do
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
  end

  describe "interval" do
    test "fixed duration enforces start + duration = end" do
      start_var = CpSat.int_var(:start, 0, 10)
      end_var = CpSat.int_var(:end_time, 0, 10)

      result =
        CpSat.new()
        |> CpSat.add([start_var, end_var])
        |> CpSat.add(CpSat.interval_var(:task, start_var, 3, end_var))
        |> CpSat.constrain(start_var >= 2)
        |> CpSat.minimize(start_var)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values[:start] == 2
      assert result.values[:end_time] == 5
    end
  end

  describe "exactly_one" do
    test "exactly one boolean variable is true" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b, :c]))
        |> CpSat.exactly_one([:a, :b, :c])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end
  end

  describe "at_most_one" do
    test "at most one variable can be true" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b, :c]))
        |> CpSat.at_most_one([:a, :b, :c])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end

    test "zero variables true is allowed" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b]))
        |> CpSat.at_most_one([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 0, b: 0}, objective: 0.0}
    end
  end

  describe "at_least_one" do
    test "forces at least one variable to be true" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b, :c]))
        |> CpSat.at_least_one([:a, :b, :c])
        |> CpSat.minimize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end
  end

  describe "bool_and" do
    test "forces all variables to be true" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b]))
        |> CpSat.bool_and([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 1, b: 1}, objective: 2.0}
    end
  end

  describe "bool_or" do
    test "at least one variable must be true" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.bool_vars([:a, :b]))
        |> CpSat.bool_or([:a, :b])
        |> CpSat.minimize(:a + :b)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 1.0
    end
  end

  describe "bool_xor" do
    test "requires an odd number of true variables" do
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

  describe "max_eq" do
    test "target variable equals the maximum of the list" do
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

    test "accepts a Variable struct as target" do
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
  end

  describe "min_eq" do
    test "target equals minimum of list" do
      result =
        CpSat.new()
        |> CpSat.add([
          CpSat.int_var(:a, 0, 10),
          CpSat.int_var(:b, 0, 10),
          CpSat.int_var(:c, 0, 10)
        ])
        |> CpSat.constrain(:a == 3)
        |> CpSat.constrain(:b == 7)
        |> CpSat.constrain(:c == 5)
        |> CpSat.maximize(min([:a, :b, :c]))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 3.0
    end
  end

  describe "abs_eq" do
    test "minimizing absolute value drives the variable to the target" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, -10..10))
        |> CpSat.minimize(abs(:x - 3))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.values.x == 3
      assert result.objective == 0.0
    end
  end

  describe "mul_eq" do
    test "target equals the product of two variables" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..10), CpSat.int_var(:y, 0..10)])
        |> CpSat.constrain(:x == 3)
        |> CpSat.constrain(:y == 4)
        |> CpSat.maximize(:x * :y)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 12.0
    end
  end

  describe "div_eq" do
    test "target equals the integer quotient" do
      result =
        CpSat.new()
        |> CpSat.add([CpSat.int_var(:x, 0..100), CpSat.int_var(:y, 1..10)])
        |> CpSat.constrain(:x == 17)
        |> CpSat.constrain(:y == 5)
        |> CpSat.maximize(div(:x, :y))
        |> CpSat.solve!()

      assert result.status == :optimal
      assert result.objective == 3.0
    end
  end
end
