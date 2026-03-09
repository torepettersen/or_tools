defmodule OrTools.CpSat.ConstraintTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  alias OrTools.CpSat.Constraint

  describe "Constraint.linear/3" do
    test "creates a linear constraint struct" do
      c = Constraint.linear([x: 1, y: 2], :<=, 10)
      assert c.type == :linear
      assert c.data == {[x: 1, y: 2], :<=, 10}
    end
  end

  describe "Constraint.interval/4" do
    test "creates an interval constraint struct" do
      c = Constraint.interval(:task, :start, :duration, :end_time)
      assert c.type == :interval
      assert c.data == {:task, :start, :duration, :end_time}
    end
  end

  describe "Constraint.interval_fixed/4" do
    test "creates an interval_fixed constraint struct" do
      c = Constraint.interval_fixed(:task, :start, 5, :end_time)
      assert c.type == :interval_fixed
      assert c.data == {:task, :start, 5, :end_time}
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
  end

  describe "Constraint.no_overlap/1" do
    test "creates a no_overlap constraint struct" do
      c = Constraint.no_overlap([:t1, :t2])
      assert c.type == :no_overlap
      assert c.data == [:t1, :t2]
    end
  end

  describe "Constraint.all_different/1" do
    test "creates an all_different constraint struct" do
      c = Constraint.all_different([{:a, 0}, {:b, 0}])
      assert c.type == :all_different
      assert c.data == [{:a, 0}, {:b, 0}]
    end
  end

  describe "boolean constraint constructors" do
    test "exactly_one" do
      c = Constraint.exactly_one([:a, :b, :c])
      assert c.type == :exactly_one
      assert c.data == [:a, :b, :c]
    end

    test "at_most_one" do
      c = Constraint.at_most_one([:a, :b])
      assert c.type == :at_most_one
      assert c.data == [:a, :b]
    end

    test "at_least_one" do
      c = Constraint.at_least_one([:a, :b])
      assert c.type == :at_least_one
      assert c.data == [:a, :b]
    end

    test "bool_and" do
      c = Constraint.bool_and([:a, :b])
      assert c.type == :bool_and
      assert c.data == [:a, :b]
    end

    test "bool_or" do
      c = Constraint.bool_or([:a, :b])
      assert c.type == :bool_or
      assert c.data == [:a, :b]
    end

    test "bool_xor" do
      c = Constraint.bool_xor([:a, :b])
      assert c.type == :bool_xor
      assert c.data == [:a, :b]
    end
  end

  describe "Constraint.max_eq/2" do
    test "creates a max_eq constraint struct" do
      c = Constraint.max_eq(:m, [:a, :b, :c])
      assert c.type == :max_eq
      assert c.data == {:m, [:a, :b, :c]}
    end
  end

  describe "Constraint.min_eq/2" do
    test "creates a min_eq constraint struct" do
      c = Constraint.min_eq(:m, [:a, :b])
      assert c.type == :min_eq
      assert c.data == {:m, [:a, :b]}
    end
  end

  describe "Constraint.abs_eq/3" do
    test "creates an abs_eq constraint struct" do
      c = Constraint.abs_eq(:r, [x: 1], 0)
      assert c.type == :abs_eq
      assert c.data == {:r, [x: 1], 0}
    end
  end

  describe "Constraint.mul_eq/2" do
    test "creates a mul_eq constraint struct" do
      c = Constraint.mul_eq(:p, [:x, :y])
      assert c.type == :mul_eq
      assert c.data == {:p, [:x, :y]}
    end
  end

  describe "Constraint.div_eq/3" do
    test "creates a div_eq constraint struct" do
      c = Constraint.div_eq(:q, :x, :y)
      assert c.type == :div_eq
      assert c.data == {:q, :x, :y}
    end
  end
end
