defmodule OrTools.CpSat.SolverTest do
  use ExUnit.Case, async: true
  use OrTools.CpSat

  describe "solve" do
    test "returns ok tuple with optimal result" do
      {:ok, result} =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.maximize(:x)
        |> CpSat.solve()

      assert result == %{status: :optimal, values: %{x: 10}, objective: 10.0}
    end

    test "returns infeasible for contradictory constraints" do
      {:ok, result} =
        CpSat.new()
        |> CpSat.add(CpSat.int_var(:x, 0..10))
        |> CpSat.constrain(:x >= 5)
        |> CpSat.constrain(:x <= 3)
        |> CpSat.maximize(:x)
        |> CpSat.solve()

      assert result == %{status: :infeasible, values: %{}, objective: 0.0}
    end
  end

  describe "solve_all" do
    test "enumerates all solutions" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 1..3))
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

    test "on_solution callback accumulates state in result.state" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 1..3))
        |> CpSat.all_different([:x, :y])
        |> CpSat.solve_all!(
          init: fn variables -> {variables, []} end,
          on_solution: fn solution, {variable_names, acc} ->
            {variable_names, [solution | acc]}
          end
        )

      {variable_names, solutions} = result.state
      assert variable_names == [:x, :y]
      assert length(solutions) == 6

      # With on_solution, solutions are not stored in memory
      refute result[:solutions]
      assert result.metrics.num_solutions == 6

      # Each accumulated solution has the same shape
      for solution <- solutions do
        assert Map.has_key?(solution, :values)
        assert Map.has_key?(solution, :objective)
      end
    end

    test "default init sets state to variable names" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 1..2))
        |> CpSat.solve_all!(on_solution: fn _solution, state -> state end)

      assert result.state == [:x, :y]
    end

    test "includes metrics" do
      result =
        CpSat.new()
        |> CpSat.add(CpSat.int_vars([:x, :y], 1..3))
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
        |> CpSat.add(CpSat.int_vars([:x, :y], 1..10))
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
        |> CpSat.add(CpSat.int_vars([:x, :y], 0..10))
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
