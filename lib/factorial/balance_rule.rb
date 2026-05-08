# frozen_string_literal: true

# BalanceRule — Design document for cross-period state in the AST evaluator.
#
# PROBLEM:
# The current evaluator is stateless: it evaluates each period independently.
# Pains #8 (rolling 12-month entitlement) and #10 (balance cap) require
# knowledge of accumulated balance from previous periods.
#
# DESIGN:
# Introduce a `balance_rule` wrapper that the runtime (backend) manages.
# The evaluator stays pure — the runtime injects `accumulated_balance` as a fact.
#
# ## How it works:
#
# 1. The AST program has an optional top-level `balance_rule` section:
#    {
#      "balance_rule": {
#        "type": "rolling",           // or "capped", "carry_over"
#        "window_months": 12,         // for rolling
#        "cap": 40,                   // for capped
#        "carry_over_max": 5,         // for carry_over
#        "expiry_months": 3           // for carry_over
#      },
#      "rule": { ... }               // the normal accrual AST
#    }
#
# 2. The runtime (backend service) calls the evaluator month by month,
#    injecting `facts.accumulated_balance` before each evaluation:
#
#    balance = 0
#    results = periods.map do |period|
#      facts[:accumulated_balance] = balance
#      facts[:balance_available] = apply_balance_rule(balance, balance_rule, period)
#      accrued = Evaluator.evaluate(program, facts, period)
#      balance += accrued
#      balance = apply_cap(balance, balance_rule) if balance_rule["type"] == "capped"
#      accrued
#    end
#
# 3. For rolling windows, the runtime tracks a sliding window:
#
#    def apply_rolling(accruals_history, window_months)
#      # Sum of accruals in the last `window_months` periods
#      accruals_history.last(window_months).sum
#    end
#
# ## Why this works:
# - The evaluator remains pure and deterministic (no side effects)
# - Cross-period state is managed by the runtime, not the AST
# - The AST can reference `facts.accumulated_balance` for cap logic
# - New balance rules = new runtime strategies, not new AST node types
#
# ## AST programs for #8 and #10:
#
# Pain #8 (UK rolling sick): The AST itself is simple (accrue 0 sick days
# as entitlement). The *availability* is computed by the runtime:
#   available = max_entitlement - sum(sick_days_taken_in_last_12_months)
# This isn't really an accrual program — it's an entitlement window.
# The AST handles the accrual side; the balance_rule handles availability.
#
# Pain #10 (overtime cap at 40h): The AST computes raw accrual, then the
# runtime applies: effective_accrual = min(raw, max(0, cap - accumulated))
# The AST can express this directly using `facts.accumulated_balance`:
#   accrue(min(computed, max(0, cap - facts.accumulated_balance)))

module Factorial
  module BalanceRule
    # Simulate the runtime loop that would exist in the backend.
    # This is NOT part of the evaluator — it's the orchestrator.
    def self.evaluate_with_balance(program, fact_builder:, employee:, contracts:, leaves:, periods:, cycle: nil)
      balance_rule = program['balance_rule']
      accumulated = BigDecimal('0')
      history = []

      periods.map do |period|
        facts = fact_builder.facts_for(
          employee: employee, contracts: contracts, leaves: leaves,
          period: period, cycle: cycle
        )

        # Inject accumulated balance as a fact
        facts[:accumulated_balance] = accumulated
        facts[:balance_available] = available_balance(accumulated, balance_rule, history)

        accrued = AccrualPoc::EvaluatorRuby.evaluate(program, facts, period)

        # Apply cap if needed
        if balance_rule && balance_rule['type'] == 'capped'
          cap = BigDecimal(balance_rule['cap'].to_s)
          effective = [accrued, [BigDecimal('0'), cap - accumulated].max].min
          accumulated += effective
          history << effective
          effective
        else
          accumulated += accrued
          history << accrued
          accrued
        end
      end
    end

    def self.available_balance(accumulated, balance_rule, history)
      return accumulated if balance_rule.nil?

      case balance_rule['type']
      when 'rolling'
        window = balance_rule['window_months'] || 12
        history.last(window).sum
      when 'capped'
        cap = BigDecimal(balance_rule['cap'].to_s)
        [cap - accumulated, BigDecimal('0')].max
      else
        accumulated
      end
    end
  end
end
