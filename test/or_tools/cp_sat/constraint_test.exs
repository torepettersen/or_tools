defmodule OrTools.CpSat.ConstraintTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  alias OrTools.CpSat.Constraint

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
        |> CpSat.add(CpSat.int_vars([:x, :y, :z], 0..50))
        |> CpSat.constrain(2 * :x + 7 * :y + 3 * :z <= 50)
        |> CpSat.constrain(3 * :x - 5 * :y + 7 * :z <= 45)
        |> CpSat.constrain(5 * :x + 2 * :y - 6 * :z <= 37)
        |> CpSat.maximize(2 * :x + 2 * :y + 3 * :z)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 7, y: 3, z: 5}, objective: 35.0}
    end

    test "collected into model via for into:" do
      vars = [:x, :y, :z]

      model =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :z], 0..10))

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

    test "inspect" do
      assert inspect(CpSat.constrain(2 * :x + 3 * :y <= 10)) == "#Constraint<2*x + 3*y <= 10>"
    end
  end

  describe "all_different" do
    test "keeps x, y, z at distinct values" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :z], 1..3))
        |> CpSat.all_different([:x, :y, :z])
        |> CpSat.maximize(:x + :y + :z)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert Enum.sort(Map.values(result.values)) == [1, 2, 3]
    end

    test "with expr offset keeps offset values distinct" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c], 0..4))
        |> CpSat.all_different([CpSat.expr(:a + 1), CpSat.expr(:b + 1), CpSat.expr(:c + 1)])
        |> CpSat.maximize(:a + :b + :c)
        |> CpSat.solve!()

      assert result.status == :optimal
      assert Enum.sort(Map.values(result.values)) == [2, 3, 4]
    end

    test "inspect" do
      assert inspect(Constraint.all_different([:a, :b, :c])) ==
               "#Constraint<all_different(:a, :b, :c)>"
    end
  end

  describe "no_overlap" do
    test "prevents two tasks from overlapping" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:s1, :e1, :s2, :e2], 0..10))
        |> CpSat.add(CpSat.interval_var(:t1, :s1, 3, :e1))
        |> CpSat.add(CpSat.interval_var(:t2, :s2, 3, :e2))
        |> CpSat.no_overlap([:t1, :t2])
        |> CpSat.constrain(:s2 < :s1)
        |> CpSat.minimize(:s1 + :s2)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{s1: 3, e1: 6, s2: 0, e2: 3}, objective: 3.0}
    end

    test "inspect" do
      assert inspect(Constraint.no_overlap([:t1, :t2])) == "#Constraint<no_overlap(:t1, :t2)>"
    end
  end

  describe "min_eq" do
    test "target variable equals the minimum of the list" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c, :m], 0..10))
        |> CpSat.constrain(:a == 3)
        |> CpSat.constrain(:b == 7)
        |> CpSat.constrain(:c == 5)
        |> CpSat.min_eq(:m, [:a, :b, :c])
        |> CpSat.maximize(:m)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 3, b: 7, c: 5, m: 3}, objective: 3.0}
    end

    test "accepts a Variable struct as target" do
      m_var = CpSat.int_var(:m, 0, 10)

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c], 0..10))
        |> CpSat.add(m_var)
        |> CpSat.constrain(:a == 3)
        |> CpSat.constrain(:b == 7)
        |> CpSat.constrain(:c == 5)
        |> CpSat.min_eq(m_var, [:a, :b, :c])
        |> CpSat.maximize(:m)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 3, b: 7, c: 5, m: 3}, objective: 3.0}
    end

    test "inspect" do
      assert inspect(Constraint.min_eq(:m, [:a, :b, :c])) == "#Constraint<m = min(:a, :b, :c)>"
    end
  end

  describe "max_eq" do
    test "target variable equals the maximum of the list" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c, :m], 0..10))
        |> CpSat.constrain(:a == 3)
        |> CpSat.constrain(:b == 7)
        |> CpSat.constrain(:c == 5)
        |> CpSat.max_eq(:m, [:a, :b, :c])
        |> CpSat.minimize(:m)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 3, b: 7, c: 5, m: 7}, objective: 7.0}
    end

    test "accepts a Variable struct as target" do
      m_var = CpSat.int_var(:m, 0, 10)

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:a, :b, :c], 0..10))
        |> CpSat.add(m_var)
        |> CpSat.constrain(:a == 3)
        |> CpSat.constrain(:b == 7)
        |> CpSat.constrain(:c == 5)
        |> CpSat.max_eq(m_var, [:a, :b, :c])
        |> CpSat.minimize(:m)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{a: 3, b: 7, c: 5, m: 7}, objective: 7.0}
    end

    test "inspect" do
      assert inspect(Constraint.max_eq(:m, [:a, :b, :c])) == "#Constraint<m = max(:a, :b, :c)>"
    end
  end

  describe "mul_eq" do
    test "target equals the product of two variables" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :t], 0..20))
        |> CpSat.constrain(:x == 3)
        |> CpSat.constrain(:y == 4)
        |> CpSat.mul_eq(:t, [:x, :y])
        |> CpSat.maximize(:t)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 3, y: 4, t: 12}, objective: 12.0}
    end

    test "inspect" do
      assert inspect(Constraint.mul_eq(:t, [:x, :y])) == "#Constraint<t = x * y>"
    end
  end

  describe "div_eq" do
    test "target equals the integer quotient" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y, :t], 1..20))
        |> CpSat.constrain(:x == 17)
        |> CpSat.constrain(:y == 5)
        |> CpSat.div_eq(:t, :x, :y)
        |> CpSat.maximize(:t)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: 17, y: 5, t: 3}, objective: 3.0}
    end

    test "inspect" do
      assert inspect(Constraint.div_eq(:t, :x, :y)) == "#Constraint<t = x div y>"
    end
  end

  describe "abs_eq" do
    test "target equals the absolute value of a variable" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :t], -10..10))
        |> CpSat.constrain(:x == -7)
        |> CpSat.abs_eq(:t, :x)
        |> CpSat.maximize(:t)
        |> CpSat.solve!()

      assert result == %{status: :optimal, values: %{x: -7, t: 7}, objective: 7.0}
    end

    test "inspect" do
      assert inspect(Constraint.abs_eq(:t, :x)) == "#Constraint<t = abs(x)>"
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

      assert result.objective == 1.0
      assert Enum.sort(Map.values(result.values)) == [0, 0, 1]
    end

    test "inspect" do
      assert inspect(Constraint.exactly_one([:a, :b, :c])) ==
               "#Constraint<exactly_one(:a, :b, :c)>"
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

      assert result.objective == 1.0
      assert Enum.sort(Map.values(result.values)) == [0, 0, 1]
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

    test "inspect" do
      assert inspect(Constraint.at_most_one([:a, :b])) == "#Constraint<at_most_one(:a, :b)>"
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

      assert result.objective == 1.0
      assert Enum.sort(Map.values(result.values)) == [0, 0, 1]
    end

    test "inspect" do
      assert inspect(Constraint.at_least_one([:a, :b, :c])) ==
               "#Constraint<at_least_one(:a, :b, :c)>"
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

    test "inspect" do
      assert inspect(Constraint.bool_and([:a, :b])) == "#Constraint<bool_and(:a, :b)>"
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

      assert result.objective == 1.0
      assert Enum.sort(Map.values(result.values)) == [0, 1]
    end

    test "inspect" do
      assert inspect(Constraint.bool_or([:a, :b])) == "#Constraint<bool_or(:a, :b)>"
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

      assert result.objective == 1.0
      assert Enum.sort(Map.values(result.values)) == [0, 1]
    end

    test "inspect" do
      assert inspect(Constraint.bool_xor([:a, :b])) == "#Constraint<bool_xor(:a, :b)>"
    end
  end

  describe "runtime values" do
    test "atom variable bound at runtime" do
      x = :x
      y = :y

      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 0..10))
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
end
