defmodule OrTools.CpSat.ScoreTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  describe "score" do
    test "scores added before maximize are used" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.score(:x)
        |> CpSat.maximize()
        |> CpSat.solve!()

      assert result.values.x == 10
    end

    test "scores added after maximize are used" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.maximize()
        |> CpSat.score(:x)
        |> CpSat.solve!()

      assert result.values.x == 10
    end

    test "scores collected into model via into:" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 0..10))
        |> then(fn model ->
          for name <- [:x, :y], into: model do
            CpSat.score(name)
          end
        end)
        |> CpSat.maximize()
        |> CpSat.solve!()

      assert result.values.x == 10
      assert result.values.y == 10
    end

    test "scores and direction can be interleaved" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.score(:x)
        |> CpSat.maximize()
        |> CpSat.add(CpSat.int_var(:y, 0..5))
        |> CpSat.score(:y)
        |> CpSat.solve!()

      assert result.values.x == 10
      assert result.values.y == 5
    end

    test "score with minimize" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.score(:x)
        |> CpSat.minimize()
        |> CpSat.solve!()

      assert result.values.x == 0
    end

    test "validate errors when score added but no direction set" do
      {:error, message} =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.score(:x)
        |> CpSat.validate()

      assert message =~ "maximize"
      assert message =~ "minimize"
    end
  end
end
