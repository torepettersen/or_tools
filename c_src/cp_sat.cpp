#include <fine.hpp>
#include <ortools/sat/cp_model.h>

#include <map>
#include <string>
#include <vector>

namespace or_sat = operations_research::sat;

// Var: {name_atom, lb, ub}
struct VarDef {
  fine::Atom name;
  int64_t lb;
  int64_t ub;
};

// Linear term: {var_name_atom, coefficient}
struct LinearTerm {
  fine::Atom var;
  int64_t coeff;
};

// Linear constraint: {[{var, coeff}, ...], op_atom, rhs_int}
struct LinearConstraint {
  std::vector<LinearTerm> terms;
  fine::Atom op;
  int64_t rhs;
};

// All-different constraint: {:all_different, [var_name, ...]}
// We'll handle this as a variant in the constraint list

// Objective: {:maximize | :minimize, [{var, coeff}, ...]}
struct Objective {
  fine::Atom sense;
  std::vector<LinearTerm> terms;
};

// Result value per variable
struct VarValue {
  fine::Atom name;
  int64_t value;
};

// Build a LinearExpr from terms and a var lookup map
static or_sat::LinearExpr build_expr(
    const std::vector<LinearTerm> &terms,
    const std::map<std::string, or_sat::IntVar> &var_map) {
  or_sat::LinearExpr expr;
  for (const auto &t : terms) {
    auto it = var_map.find(t.var.to_string());
    if (it == var_map.end()) {
      throw std::runtime_error("Unknown variable: " + t.var.to_string());
    }
    expr += or_sat::LinearExpr(it->second) * t.coeff;
  }
  return expr;
}

// solve(vars, constraints, objective_or_nil)
//
// vars: [{name, lb, ub}, ...]
// constraints: [{[{var, coeff}, ...], op, rhs}, ...] | [{:all_different, [var, ...]}, ...]
// objective: nil | {:maximize | :minimize, [{var, coeff}, ...]}
//
// Returns: {status, %{name => value}, objective_value}
std::tuple<fine::Atom, std::map<fine::Atom, int64_t>, double> solve(
    ErlNifEnv *env,
    std::vector<std::tuple<fine::Atom, int64_t, int64_t>> vars,
    fine::Term constraints_term,
    fine::Term objective_term) {

  or_sat::CpModelBuilder builder;
  std::map<std::string, or_sat::IntVar> var_map;
  std::vector<std::pair<std::string, or_sat::IntVar>> var_order;

  // Create variables
  for (const auto &[name, lb, ub] : vars) {
    auto var = builder.NewIntVar(operations_research::Domain(lb, ub))
                   .WithName(name.to_string());
    var_map[name.to_string()] = var;
    var_order.push_back({name.to_string(), var});
  }

  // Decode and add constraints
  unsigned int num_constraints;
  if (!enif_get_list_length(env, constraints_term, &num_constraints)) {
    throw std::invalid_argument("constraints must be a list");
  }

  ERL_NIF_TERM head, tail;
  auto list = (ERL_NIF_TERM)constraints_term;
  while (enif_get_list_cell(env, list, &head, &tail)) {
    // Each constraint is either:
    // {:all_different, [var_names...]}
    // {[{var, coeff}...], op_atom, rhs}
    int arity;
    const ERL_NIF_TERM *elems;
    if (!enif_get_tuple(env, head, &arity, &elems)) {
      throw std::invalid_argument("constraint must be a tuple");
    }

    if (arity == 2) {
      // {:all_different, [var_names]}
      auto tag = fine::decode<fine::Atom>(env, elems[0]);
      if (tag == "all_different") {
        auto names = fine::decode<std::vector<fine::Atom>>(env, elems[1]);
        std::vector<or_sat::IntVar> int_vars;
        for (const auto &n : names) {
          int_vars.push_back(var_map.at(n.to_string()));
        }
        builder.AddAllDifferent(int_vars);
      }
    } else if (arity == 4) {
      // {:abs_eq, target_var, [{var, coeff}, ...], constant}
      auto tag = fine::decode<fine::Atom>(env, elems[0]);
      if (tag == "abs_eq") {
        auto target_name = fine::decode<fine::Atom>(env, elems[1]);
        auto terms = fine::decode<std::vector<std::tuple<fine::Atom, int64_t>>>(env, elems[2]);
        auto constant = fine::decode<int64_t>(env, elems[3]);

        or_sat::LinearExpr expr;
        for (const auto &[var_name, coeff] : terms) {
          expr += or_sat::LinearExpr(var_map.at(var_name.to_string())) * coeff;
        }
        expr += constant;

        builder.AddAbsEquality(var_map.at(target_name.to_string()), expr);
      }
    } else if (arity == 3 && enif_is_atom(env, elems[0])) {
      // {:mul_eq, target_var, [factor_var, ...]}
      auto tag = fine::decode<fine::Atom>(env, elems[0]);
      if (tag == "mul_eq") {
        auto target_name = fine::decode<fine::Atom>(env, elems[1]);
        auto factor_names = fine::decode<std::vector<fine::Atom>>(env, elems[2]);

        std::vector<or_sat::IntVar> factors;
        for (const auto &name : factor_names) {
          factors.push_back(var_map.at(name.to_string()));
        }

        builder.AddMultiplicationEquality(var_map.at(target_name.to_string()), factors);
      }
    } else if (arity == 3) {
      // {[{var, coeff}...], op, rhs}
      auto terms = fine::decode<std::vector<std::tuple<fine::Atom, int64_t>>>(env, elems[0]);
      auto op = fine::decode<fine::Atom>(env, elems[1]);
      auto rhs = fine::decode<int64_t>(env, elems[2]);

      or_sat::LinearExpr expr;
      for (const auto &[var_name, coeff] : terms) {
        expr += or_sat::LinearExpr(var_map.at(var_name.to_string())) * coeff;
      }

      auto rhs_expr = or_sat::LinearExpr(rhs);

      if (op == "<=") {
        builder.AddLessOrEqual(expr, rhs_expr);
      } else if (op == ">=") {
        builder.AddGreaterOrEqual(expr, rhs_expr);
      } else if (op == "==") {
        builder.AddEquality(expr, rhs_expr);
      } else if (op == "!=") {
        builder.AddNotEqual(expr, rhs_expr);
      } else if (op == "<") {
        builder.AddLessThan(expr, rhs_expr);
      } else if (op == ">") {
        builder.AddGreaterThan(expr, rhs_expr);
      } else {
        throw std::runtime_error("Unknown operator: " + op.to_string());
      }
    }

    list = tail;
  }

  // Decode and set objective
  if (!enif_is_atom(env, objective_term)) {
    // Not nil, so it's {:maximize | :minimize, [{var, coeff}...]}
    int obj_arity;
    const ERL_NIF_TERM *obj_elems;
    if (enif_get_tuple(env, objective_term, &obj_arity, &obj_elems) && obj_arity == 2) {
      auto sense = fine::decode<fine::Atom>(env, obj_elems[0]);
      auto terms = fine::decode<std::vector<std::tuple<fine::Atom, int64_t>>>(env, obj_elems[1]);

      or_sat::LinearExpr expr;
      for (const auto &[var_name, coeff] : terms) {
        expr += or_sat::LinearExpr(var_map.at(var_name.to_string())) * coeff;
      }

      if (sense == "maximize") {
        builder.Maximize(expr);
      } else if (sense == "minimize") {
        builder.Minimize(expr);
      }
    }
  }

  // Solve
  auto response = or_sat::Solve(builder.Build());

  // Build status atom
  fine::Atom status_atom("unknown");
  switch (response.status()) {
    case or_sat::CpSolverStatus::OPTIMAL:
      status_atom = fine::Atom("optimal"); break;
    case or_sat::CpSolverStatus::FEASIBLE:
      status_atom = fine::Atom("feasible"); break;
    case or_sat::CpSolverStatus::INFEASIBLE:
      status_atom = fine::Atom("infeasible"); break;
    case or_sat::CpSolverStatus::MODEL_INVALID:
      status_atom = fine::Atom("model_invalid"); break;
    default:
      break;
  }

  // Build values map
  std::map<fine::Atom, int64_t> values;
  if (response.status() == or_sat::CpSolverStatus::OPTIMAL ||
      response.status() == or_sat::CpSolverStatus::FEASIBLE) {
    for (const auto &[name, var] : var_order) {
      values[fine::Atom(name)] =
          or_sat::SolutionIntegerValue(response, or_sat::LinearExpr(var));
    }
  }

  double objective = response.objective_value();

  return {status_atom, values, objective};
}

FINE_NIF(solve, 0);
FINE_INIT("Elixir.OrTools.NIF");
