defmodule OrTools.CpSat.ExprTest do
  use ExUnit.Case
  alias OrTools.CpSat.Expr

  describe "new" do
    test "zero expression" do
      assert %Expr{terms: [], const: 0, special: []} = Expr.new()
    end

    test "from variable" do
      assert %Expr{terms: [x: 1]} = Expr.new(:x)
    end

    test "from constant" do
      assert %Expr{const: 42} = Expr.new(42)
    end

    test "from weighted variable" do
      assert %Expr{terms: [{:x, 5}]} = Expr.new({:x, 5})
    end

    test "passthrough Expr" do
      expr = Expr.new(:x)
      assert Expr.new(expr) == expr
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
      expr = %Expr{special: [{:abs, Expr.new(:x), 1}, {:abs, Expr.new(:y), 3}]}
      result = Expr.scale(expr, 5)
      assert [{:abs, _, 5}, {:abs, _, 15}] = result.special
    end

    test "add combines special terms" do
      a = %Expr{special: [{:abs, Expr.new(:x), 1}]}
      b = %Expr{special: [{:abs, Expr.new(:y), 1}]}
      result = Expr.add(a, b)
      assert length(result.special) == 2
    end
  end

  describe "inspect" do
    test "simple variable" do
      assert inspect(Expr.new(:x)) == "#Expr<x>"
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
      assert inspect(Expr.new(42)) == "#Expr<42>"
    end
  end

  describe "collectable" do
    test "for comprehension with into" do
      result = for v <- [:x, :y, :z], into: %Expr{}, do: Expr.new(v)
      assert result.terms == [{:x, 1}, {:y, 1}, {:z, 1}]
    end

    test "for comprehension with scaled terms" do
      result =
        for {v, c} <- [x: 2, y: 3], into: %Expr{} do
          Expr.new({v, c})
        end

      assert result.terms == [{:x, 2}, {:y, 3}]
    end

    test "collects Expr values" do
      a = %Expr{terms: [{:x, 1}], const: 5}
      b = %Expr{terms: [{:y, 2}], const: 3}
      result = for e <- [a, b], into: %Expr{}, do: e
      assert result.terms == [{:x, 1}, {:y, 2}]
      assert result.const == 8
    end
  end
end
