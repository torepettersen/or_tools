defmodule OrTools.CpSat.Objective do
  @moduledoc false

  alias OrTools.CpSat.Expr

  @doc "Merges new linear terms into an objective, accumulating across multiple score calls."
  def merge_score(nil, new_terms) do
    {nil, new_terms}
  end

  def merge_score({sense, existing_terms}, new_terms) do
    {sense, Expr.merge_terms(existing_terms ++ new_terms)}
  end

  @doc "Sets the optimization direction on an existing or new objective."
  def set_direction(nil, sense) do
    {sense, []}
  end

  def set_direction({_sense, terms}, sense) do
    {sense, terms}
  end

  @doc "Validates the objective against declared variable names."
  def validate(nil, _declared) do
    :ok
  end

  def validate({nil, _terms}, _declared) do
    {:error, "score expressions were added but CpSat.maximize/1 or CpSat.minimize/1 was never called"}
  end

  def validate({_sense, terms}, declared) do
    check_terms(terms, declared)
  end

  # --- Compile-time AST helpers (used by CpSat score/maximize/minimize macros) ---

  @doc false
  def build_score_ast(expr) do
    terms_ast = Expr.quote_collect_terms(expr)
    quote do: %OrTools.CpSat.Score{expr: unquote(terms_ast)}
  end

  @doc false
  def build_score_ast(model, expr) do
    terms_ast = Expr.quote_collect_terms(expr)
    quote do: OrTools.CpSat.add(unquote(model), %OrTools.CpSat.Score{expr: unquote(terms_ast)})
  end

  @doc false
  def build_objective_ast(model, sense, expr) do
    terms_ast = Expr.quote_collect_terms(expr)

    quote do
      OrTools.CpSat.__build_objective__(unquote(model), unquote(sense), unquote(terms_ast))
    end
  end

  defp check_terms(terms, declared) do
    unknown =
      terms
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&MapSet.member?(declared, &1))

    case unknown do
      [] ->
        :ok

      unknown ->
        declared_list = declared |> MapSet.to_list() |> Enum.sort()

        {:error,
         "unknown variable(s) #{inspect(unknown)} in model. " <>
           "Declared variables: #{inspect(declared_list)}"}
    end
  end
end
