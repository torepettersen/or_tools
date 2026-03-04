defmodule OrTools.CpSat.ExprTest do
  use ExUnit.Case
  alias OrTools.CpSat.Expr

  describe "constructors" do
    test "new creates zero expression" do
      assert %Expr{terms: [], const: 0, special: []} = Expr.new()
    end

    test "var creates single variable" do
      assert %Expr{terms: [x: 1]} = Expr.var(:x)
    end

    test "const creates constant" do
      assert %Expr{const: 42} = Expr.const(42)
    end
  end

  describe "arithmetic" do
    test "add combines terms" do
      a = %Expr{terms: [{:x, 2}], const: 1}
      b = %Expr{terms: [{:y, 3}], const: 4}
      result = Expr.add(a, b)
      assert result.terms == [{:x, 2}, {:y, 3}]
      assert result.const == 5
    end

    test "subtract negates and adds" do
      a = %Expr{terms: [{:x, 2}], const: 10}
      b = %Expr{terms: [{:y, 3}], const: 4}
      result = Expr.subtract(a, b)
      assert result.terms == [{:x, 2}, {:y, -3}]
      assert result.const == 6
    end

    test "negate flips all signs" do
      expr = %Expr{terms: [{:x, 2}, {:y, -3}], const: 5}
      result = Expr.negate(expr)
      assert result.terms == [{:x, -2}, {:y, 3}]
      assert result.const == -5
    end

    test "scale multiplies everything" do
      expr = %Expr{terms: [{:x, 2}, {:y, 3}], const: 5}
      result = Expr.scale(expr, 10)
      assert result.terms == [{:x, 20}, {:y, 30}]
      assert result.const == 50
    end

    test "scale applies to special terms" do
      expr = %Expr{special: [{:abs, Expr.var(:x), 1}, {:pow, Expr.var(:y), 2, 3}]}
      result = Expr.scale(expr, 5)
      assert [{:abs, _, 5}, {:pow, _, 2, 15}] = result.special
    end

    test "add combines special terms" do
      a = %Expr{special: [{:abs, Expr.var(:x), 1}]}
      b = %Expr{special: [{:pow, Expr.var(:y), 2, 1}]}
      result = Expr.add(a, b)
      assert length(result.special) == 2
    end
  end

  describe "coerce" do
    test "passes through Expr" do
      expr = Expr.var(:x)
      assert Expr.coerce(expr) == expr
    end

    test "converts atom to var" do
      assert Expr.coerce(:x) == Expr.var(:x)
    end

    test "converts integer to const" do
      assert Expr.coerce(42) == Expr.const(42)
    end

    test "converts {atom, int} tuple" do
      assert Expr.coerce({:x, 5}) == %Expr{terms: [{:x, 5}]}
    end
  end

  describe "from_runtime" do
    test "handles Expr" do
      expr = Expr.var(:x)
      assert Expr.from_runtime(expr) == expr
    end

    test "handles atom" do
      assert Expr.from_runtime(:x) == Expr.var(:x)
    end

    test "handles integer" do
      assert Expr.from_runtime(42) == Expr.const(42)
    end
  end

  describe "inspect" do
    test "simple variable" do
      assert inspect(Expr.var(:x)) == "#Expr<x>"
    end

    test "weighted variable" do
      assert inspect(%Expr{terms: [{:x, 3}]}) == "#Expr<3*x>"
    end

    test "multiple terms" do
      assert inspect(%Expr{terms: [{:x, 2}, {:y, 3}]}) == "#Expr<2*x + 3*y>"
    end

    test "negative terms" do
      assert inspect(%Expr{terms: [{:x, 2}, {:y, -3}]}) == "#Expr<2*x - 3*y>"
    end

    test "with constant" do
      assert inspect(%Expr{terms: [{:x, 1}], const: 5}) == "#Expr<x + 5>"
    end

    test "zero expression" do
      assert inspect(Expr.new()) == "#Expr<0>"
    end

    test "constant only" do
      assert inspect(Expr.const(42)) == "#Expr<42>"
    end
  end
end
