#include <fine.hpp>
#include <ortools/sat/cp_model.h>
#include <ortools/sat/cp_model_solver.h>

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

// All-different constraint: {:all_different, [{var_name, offset}, ...]}
// Offsets are applied via LinearExpr, so no auxiliary variables are needed.

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

// Holds builder, var_map, var_order, and interval_map after building a model.
struct BuiltModel {
  or_sat::CpModelBuilder builder;
  std::map<std::string, or_sat::IntVar> var_map;
  std::vector<std::pair<std::string, or_sat::IntVar>> var_order;
  std::map<std::string, or_sat::IntervalVar> interval_map;
};

// Apply a keyword list of solver parameters to a SatParameters object.
// Unknown keys are silently ignored.
static void apply_params(
    ErlNifEnv *env,
    or_sat::SatParameters &parameters,
    fine::Term params_term) {

  auto params = fine::decode<std::vector<std::tuple<fine::Atom, fine::Term>>>(env, params_term);

  for (const auto &[key, value] : params) {
    if (key == "max_time_in_seconds") {
      ErlNifSInt64 int_val;
      double dbl_val;
      if (enif_get_int64(env, value, &int_val)) {
        dbl_val = static_cast<double>(int_val);
      } else {
        dbl_val = fine::decode<double>(env, value);
      }
      parameters.set_max_time_in_seconds(dbl_val);
    } else if (key == "max_number_of_conflicts") {
      parameters.set_max_number_of_conflicts(fine::decode<int64_t>(env, value));
    } else if (key == "num_workers") {
      parameters.set_num_workers(static_cast<int32_t>(fine::decode<int64_t>(env, value)));
    } else if (key == "random_seed") {
      parameters.set_random_seed(static_cast<int32_t>(fine::decode<int64_t>(env, value)));
    } else if (key == "log_search_progress") {
      auto atom = fine::decode<fine::Atom>(env, value);
      parameters.set_log_search_progress(atom == "true");
    }
  }
}

// Synchronization handle for solve_all with on_solution callback.
// The observer waits for the Elixir handler to signal after each solution,
// allowing the handler to request an early stop via {:halt, state}.
struct SolveCtrl {
  ErlNifMutex *mtx;
  ErlNifCond *cond;
  bool processed = false;
  bool halt = false;

  SolveCtrl() {
    mtx = enif_mutex_create(const_cast<char *>("solve_ctrl_mtx"));
    cond = enif_cond_create(const_cast<char *>("solve_ctrl_cond"));
  }

  void destructor(ErlNifEnv *) {
    enif_mutex_destroy(mtx);
    enif_cond_destroy(cond);
  }
};

FINE_RESOURCE(SolveCtrl);

// new_solve_ctrl() -> resource
fine::ResourcePtr<SolveCtrl> new_solve_ctrl(ErlNifEnv *) {
  return fine::make_resource<SolveCtrl>();
}
FINE_NIF(new_solve_ctrl, 0);

// signal_solve(ctrl, :continue | :halt) -> :ok
fine::Atom signal_solve(ErlNifEnv *, fine::ResourcePtr<SolveCtrl> ctrl,
                        fine::Atom reply) {
  enif_mutex_lock(ctrl->mtx);
  ctrl->halt = (reply == "halt");
  ctrl->processed = true;
  enif_cond_signal(ctrl->cond);
  enif_mutex_unlock(ctrl->mtx);
  return fine::Atom("ok");
}
FINE_NIF(signal_solve, 0);

static fine::Atom status_to_atom(or_sat::CpSolverStatus status) {
  switch (status) {
    case or_sat::CpSolverStatus::OPTIMAL:
      return fine::Atom("optimal");
    case or_sat::CpSolverStatus::FEASIBLE:
      return fine::Atom("feasible");
    case or_sat::CpSolverStatus::INFEASIBLE:
      return fine::Atom("infeasible");
    case or_sat::CpSolverStatus::MODEL_INVALID:
      return fine::Atom("model_invalid");
    default:
      return fine::Atom("unknown");
  }
}

// Build a model from vars, constraints, and objective terms.
static BuiltModel build_model(
    ErlNifEnv *env,
    const std::vector<std::tuple<fine::Atom, int64_t, int64_t>> &vars,
    fine::Term constraints_term,
    fine::Term objective_term) {

  BuiltModel m;

  // Create variables
  for (const auto &[name, lb, ub] : vars) {
    auto var = m.builder.NewIntVar(operations_research::Domain(lb, ub))
                   .WithName(name.to_string());
    m.var_map[name.to_string()] = var;
    m.var_order.push_back({name.to_string(), var});
  }

  // Decode and add constraints
  unsigned int num_constraints;
  if (!enif_get_list_length(env, constraints_term, &num_constraints)) {
    throw std::invalid_argument("constraints must be a list");
  }

  ERL_NIF_TERM head, tail;
  auto list = (ERL_NIF_TERM)constraints_term;
  while (enif_get_list_cell(env, list, &head, &tail)) {
    int arity;
    const ERL_NIF_TERM *elems;
    if (!enif_get_tuple(env, head, &arity, &elems)) {
      throw std::invalid_argument("constraint must be a tuple");
    }

    if (arity == 2) {
      auto tag = fine::decode<fine::Atom>(env, elems[0]);

      if (tag == "no_overlap") {
        auto names = fine::decode<std::vector<fine::Atom>>(env, elems[1]);
        std::vector<or_sat::IntervalVar> intervals;
        for (const auto &name : names) {
          intervals.push_back(m.interval_map.at(name.to_string()));
        }
        m.builder.AddNoOverlap(intervals);
      } else if (tag == "all_different") {
        auto name_offsets =
            fine::decode<std::vector<std::tuple<fine::Atom, int64_t>>>(env, elems[1]);
        std::vector<or_sat::LinearExpr> exprs;
        for (const auto &[name, offset] : name_offsets) {
          exprs.push_back(
              or_sat::LinearExpr(m.var_map.at(name.to_string())) + offset);
        }
        m.builder.AddAllDifferent(exprs);
      } else {
        auto names = fine::decode<std::vector<fine::Atom>>(env, elems[1]);
        if (tag == "exactly_one") {
          std::vector<or_sat::BoolVar> bools;
          for (const auto &n : names) {
            bools.push_back(m.var_map.at(n.to_string()).ToBoolVar());
          }
          m.builder.AddExactlyOne(bools);
        } else if (tag == "at_most_one") {
          std::vector<or_sat::BoolVar> bools;
          for (const auto &n : names) {
            bools.push_back(m.var_map.at(n.to_string()).ToBoolVar());
          }
          m.builder.AddAtMostOne(bools);
        } else if (tag == "at_least_one") {
          std::vector<or_sat::BoolVar> bools;
          for (const auto &n : names) {
            bools.push_back(m.var_map.at(n.to_string()).ToBoolVar());
          }
          m.builder.AddAtLeastOne(bools);
        } else if (tag == "bool_and") {
          std::vector<or_sat::BoolVar> bools;
          for (const auto &n : names) {
            bools.push_back(m.var_map.at(n.to_string()).ToBoolVar());
          }
          m.builder.AddBoolAnd(bools);
        } else if (tag == "bool_or") {
          std::vector<or_sat::BoolVar> bools;
          for (const auto &n : names) {
            bools.push_back(m.var_map.at(n.to_string()).ToBoolVar());
          }
          m.builder.AddBoolOr(bools);
        } else if (tag == "bool_xor") {
          std::vector<or_sat::BoolVar> bools;
          for (const auto &n : names) {
            bools.push_back(m.var_map.at(n.to_string()).ToBoolVar());
          }
          m.builder.AddBoolXor(bools);
        }
      }
    } else if (arity == 4) {
      auto tag = fine::decode<fine::Atom>(env, elems[0]);
      if (tag == "abs_eq") {
        auto target_name = fine::decode<fine::Atom>(env, elems[1]);
        auto terms = fine::decode<std::vector<std::tuple<fine::Atom, int64_t>>>(env, elems[2]);
        auto constant = fine::decode<int64_t>(env, elems[3]);

        or_sat::LinearExpr expr;
        for (const auto &[var_name, coeff] : terms) {
          expr += or_sat::LinearExpr(m.var_map.at(var_name.to_string())) * coeff;
        }
        expr += constant;

        m.builder.AddAbsEquality(m.var_map.at(target_name.to_string()), expr);
      } else if (tag == "div_eq") {
        auto target_name = fine::decode<fine::Atom>(env, elems[1]);
        auto dividend_name = fine::decode<fine::Atom>(env, elems[2]);
        auto divisor_name = fine::decode<fine::Atom>(env, elems[3]);

        m.builder.AddDivisionEquality(
            m.var_map.at(target_name.to_string()),
            m.var_map.at(dividend_name.to_string()),
            m.var_map.at(divisor_name.to_string()));
      }
    } else if (arity == 5) {
      auto tag = fine::decode<fine::Atom>(env, elems[0]);
      if (tag == "interval") {
        auto interval_name = fine::decode<fine::Atom>(env, elems[1]);
        auto start_name    = fine::decode<fine::Atom>(env, elems[2]);
        auto duration_name = fine::decode<fine::Atom>(env, elems[3]);
        auto end_name      = fine::decode<fine::Atom>(env, elems[4]);

        auto interval = m.builder.NewIntervalVar(
            or_sat::LinearExpr(m.var_map.at(start_name.to_string())),
            or_sat::LinearExpr(m.var_map.at(duration_name.to_string())),
            or_sat::LinearExpr(m.var_map.at(end_name.to_string())));
        m.interval_map[interval_name.to_string()] = interval;
      } else if (tag == "interval_fixed") {
        auto interval_name = fine::decode<fine::Atom>(env, elems[1]);
        auto start_name    = fine::decode<fine::Atom>(env, elems[2]);
        auto duration      = fine::decode<int64_t>(env, elems[3]);
        auto end_name      = fine::decode<fine::Atom>(env, elems[4]);

        auto dur_var = m.builder.NewIntVar(operations_research::Domain::FromValues({duration}));
        auto interval = m.builder.NewIntervalVar(
            or_sat::LinearExpr(m.var_map.at(start_name.to_string())),
            or_sat::LinearExpr(dur_var),
            or_sat::LinearExpr(m.var_map.at(end_name.to_string())));
        m.interval_map[interval_name.to_string()] = interval;
      }
    } else if (arity == 3 && enif_is_atom(env, elems[0])) {
      auto tag = fine::decode<fine::Atom>(env, elems[0]);
      if (tag == "mul_eq") {
        auto target_name = fine::decode<fine::Atom>(env, elems[1]);
        auto factor_names = fine::decode<std::vector<fine::Atom>>(env, elems[2]);

        std::vector<or_sat::IntVar> factors;
        for (const auto &name : factor_names) {
          factors.push_back(m.var_map.at(name.to_string()));
        }

        m.builder.AddMultiplicationEquality(m.var_map.at(target_name.to_string()), factors);
      } else if (tag == "min_eq") {
        auto target_name = fine::decode<fine::Atom>(env, elems[1]);
        auto names = fine::decode<std::vector<fine::Atom>>(env, elems[2]);

        std::vector<or_sat::IntVar> int_vars;
        for (const auto &n : names) {
          int_vars.push_back(m.var_map.at(n.to_string()));
        }
        m.builder.AddMinEquality(m.var_map.at(target_name.to_string()), int_vars);
      } else if (tag == "max_eq") {
        auto target_name = fine::decode<fine::Atom>(env, elems[1]);
        auto names = fine::decode<std::vector<fine::Atom>>(env, elems[2]);

        std::vector<or_sat::IntVar> int_vars;
        for (const auto &n : names) {
          int_vars.push_back(m.var_map.at(n.to_string()));
        }
        m.builder.AddMaxEquality(m.var_map.at(target_name.to_string()), int_vars);
      }
    } else if (arity == 3) {
      auto terms = fine::decode<std::vector<std::tuple<fine::Atom, int64_t>>>(env, elems[0]);
      auto op = fine::decode<fine::Atom>(env, elems[1]);
      auto rhs = fine::decode<int64_t>(env, elems[2]);

      or_sat::LinearExpr expr;
      for (const auto &[var_name, coeff] : terms) {
        expr += or_sat::LinearExpr(m.var_map.at(var_name.to_string())) * coeff;
      }

      auto rhs_expr = or_sat::LinearExpr(rhs);

      if (op == "<=") {
        m.builder.AddLessOrEqual(expr, rhs_expr);
      } else if (op == ">=") {
        m.builder.AddGreaterOrEqual(expr, rhs_expr);
      } else if (op == "==") {
        m.builder.AddEquality(expr, rhs_expr);
      } else if (op == "!=") {
        m.builder.AddNotEqual(expr, rhs_expr);
      } else if (op == "<") {
        m.builder.AddLessThan(expr, rhs_expr);
      } else if (op == ">") {
        m.builder.AddGreaterThan(expr, rhs_expr);
      } else {
        throw std::runtime_error("Unknown operator: " + op.to_string());
      }
    }

    list = tail;
  }

  // Decode and set objective
  if (!enif_is_atom(env, objective_term)) {
    int obj_arity;
    const ERL_NIF_TERM *obj_elems;
    if (enif_get_tuple(env, objective_term, &obj_arity, &obj_elems) && obj_arity == 2) {
      auto sense = fine::decode<fine::Atom>(env, obj_elems[0]);
      auto terms = fine::decode<std::vector<std::tuple<fine::Atom, int64_t>>>(env, obj_elems[1]);

      or_sat::LinearExpr expr;
      for (const auto &[var_name, coeff] : terms) {
        expr += or_sat::LinearExpr(m.var_map.at(var_name.to_string())) * coeff;
      }

      if (sense == "maximize") {
        m.builder.Maximize(expr);
      } else if (sense == "minimize") {
        m.builder.Minimize(expr);
      }
    }
  }

  return m;
}

// Extract variable values from a CpSolverResponse
static std::map<fine::Atom, int64_t> extract_values(
    const or_sat::CpSolverResponse &response,
    const std::vector<std::pair<std::string, or_sat::IntVar>> &var_order) {
  std::map<fine::Atom, int64_t> values;
  for (const auto &[name, var] : var_order) {
    values[fine::Atom(name)] =
        or_sat::SolutionIntegerValue(response, or_sat::LinearExpr(var));
  }
  return values;
}

// solve(vars, constraints, objective_or_nil, params)
//
// Returns: {status, %{name => value}, objective_value}
std::tuple<fine::Atom, std::map<fine::Atom, int64_t>, double> solve(
    ErlNifEnv *env,
    std::vector<std::tuple<fine::Atom, int64_t, int64_t>> vars,
    fine::Term constraints_term,
    fine::Term objective_term,
    fine::Term params_term) {

  auto m = build_model(env, vars, constraints_term, objective_term);

  or_sat::SatParameters parameters;
  apply_params(env, parameters, params_term);

  or_sat::Model model;
  model.Add(or_sat::NewSatParameters(parameters));

  auto response = or_sat::SolveCpModel(m.builder.Build(), &model);

  auto status_atom = status_to_atom(response.status());

  std::map<fine::Atom, int64_t> values;
  if (response.status() == or_sat::CpSolverStatus::OPTIMAL ||
      response.status() == or_sat::CpSolverStatus::FEASIBLE) {
    values = extract_values(response, m.var_order);
  }

  double objective = response.objective_value();

  return {status_atom, values, objective};
}

// Build a stats map from a CpSolverResponse
static std::map<fine::Atom, int64_t> extract_stats(
    const or_sat::CpSolverResponse &response) {
  std::map<fine::Atom, int64_t> stats;
  stats[fine::Atom("num_conflicts")] = response.num_conflicts();
  stats[fine::Atom("num_branches")] = response.num_branches();
  // wall_time is a double; convert to microseconds for integer representation
  stats[fine::Atom("wall_time_us")] =
      static_cast<int64_t>(response.wall_time() * 1e6);
  return stats;
}

// solve_all(vars, constraints, objective_or_nil, callback_pid_or_nil, ctrl_or_nil, params)
//
// Returns: {status, [{%{name => value}, objective}, ...], %{stat => value}}
//
// When callback_pid is provided (not nil), sends {:solution, index, values, objective}
// to that process for each solution, then waits for a signal_solve/2 reply before
// continuing. If the reply is :halt, search is stopped immediately.
std::tuple<fine::Atom,
           std::vector<std::tuple<std::map<fine::Atom, int64_t>, double>>,
           std::map<fine::Atom, int64_t>>
solve_all(
    ErlNifEnv *env,
    std::vector<std::tuple<fine::Atom, int64_t, int64_t>> vars,
    fine::Term constraints_term,
    fine::Term objective_term,
    fine::Term callback_pid_term,
    fine::Term ctrl_term,
    fine::Term params_term) {

  auto m = build_model(env, vars, constraints_term, objective_term);

  auto model_proto = m.builder.Build();

  // Check if a callback pid was provided
  bool has_callback = !enif_is_atom(env, callback_pid_term);
  ErlNifPid callback_pid;
  fine::ResourcePtr<SolveCtrl> ctrl;
  if (has_callback) {
    callback_pid = fine::decode<ErlNifPid>(env, callback_pid_term);
    ctrl = fine::decode<fine::ResourcePtr<SolveCtrl>>(env, ctrl_term);
  }

  // Configure parameters: apply user params first, then force enumerate_all_solutions
  or_sat::SatParameters parameters;
  apply_params(env, parameters, params_term);
  parameters.set_enumerate_all_solutions(true);

  // Collect solutions via observer callback.
  // When a callback pid is provided, we only count solutions (don't store them).
  std::vector<std::tuple<std::map<fine::Atom, int64_t>, double>> solutions;
  auto &var_order = m.var_order;
  int64_t solution_count = 0;

  or_sat::Model model;
  model.Add(or_sat::NewSatParameters(parameters));
  model.Add(or_sat::NewFeasibleSolutionObserver(
      [&](const or_sat::CpSolverResponse &response) {
        auto values = extract_values(response, var_order);
        double objective = response.objective_value();
        solution_count++;

        if (has_callback) {
          auto msg_env = enif_alloc_env();
          auto tag = fine::encode(msg_env, fine::Atom("solution"));
          auto idx = fine::encode(msg_env, solution_count);
          auto vals = fine::encode(msg_env, values);
          auto obj = fine::encode(msg_env, objective);
          auto msg = enif_make_tuple4(msg_env, tag, idx, vals, obj);
          enif_send(env, &callback_pid, msg_env, msg);
          enif_free_env(msg_env);

          // Wait for handler to signal continue or halt
          enif_mutex_lock(ctrl->mtx);
          while (!ctrl->processed) {
            enif_cond_wait(ctrl->cond, ctrl->mtx);
          }
          bool should_halt = ctrl->halt;
          ctrl->processed = false;
          enif_mutex_unlock(ctrl->mtx);

          if (should_halt) {
            or_sat::StopSearch(&model);
          }
        } else {
          solutions.push_back({values, objective});
        }
      }));

  auto response = or_sat::SolveCpModel(model_proto, &model);

  auto status_atom = status_to_atom(response.status());
  auto stats = extract_stats(response);
  stats[fine::Atom("num_solutions")] = solution_count;

  return {status_atom, solutions, stats};
}

FINE_NIF(solve, ERL_NIF_DIRTY_JOB_CPU_BOUND);
FINE_NIF(solve_all, ERL_NIF_DIRTY_JOB_CPU_BOUND);
FINE_INIT("Elixir.OrTools.NIF");
