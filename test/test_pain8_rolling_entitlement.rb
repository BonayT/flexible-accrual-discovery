# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/factorial/balance_rule'

# Pain #8 — Missing Rolling Entitlement (UK sick days)
#
# UK: 0 sick days accrued per rolling 12-month period.
# If 5 days were taken on 2024-12-10, those 5 days become available again on 2025-12-10.
# Platform only supports fixed-period resets (calendar year / accrual cycle).
#
# This test demonstrates the balance_rule concept: the runtime manages a rolling
# 12-month window while the AST handles the per-period accrual calculation.
class TestPain8RollingEntitlement < Minitest::Test
  include TestHelpers

  # The AST program is simple: accrue a fixed monthly entitlement.
  # The rolling window logic lives in the runtime (BalanceRule module).
  # In production, "available sick days" = max_entitlement - sum(used_in_last_12_months)
  #
  # For this skeleton, we model it as: accrue 2.33 days/month (28 statutory sick days/12)
  # with a rolling 12-month cap managed by the runtime.
  PROGRAM = {
    'balance_rule' => {
      'type' => 'rolling',
      'window_months' => 12
    },
    'params' => { 'monthly_entitlement' => 2.333 },
    'rule' => {
      'type' => 'accrue',
      'amount' => { 'type' => 'param', 'name' => 'monthly_entitlement' }
    }
  }.freeze

  def setup
    @employee = Factorial::Employee.new(
      id: 11, hired_on: Date.new(2022, 1, 1), terminated_on: nil,
      full_name: 'James Wilson', country: 'UK', children_count: 0, gender: 'male'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 40, days_per_week: 5, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2022, 1, 1), end_date: nil
    )
  end

  def test_rolling_12_month_accrual
    periods = (1..12).map { |m| build_period(2026, m) }

    results = Factorial::BalanceRule.evaluate_with_balance(
      PROGRAM,
      fact_builder: Factorial::AccrualFactBuilder.new,
      employee: @employee,
      contracts: [@contract],
      leaves: [],
      periods: periods,
      cycle: { start: Date.new(2026, 1, 1), end: Date.new(2026, 12, 31) }
    )

    # Each month accrues 2.333 (rolling window doesn't cap accrual, only availability)
    results.each_with_index do |r, i|
      assert_equal BigDecimal('2.333'), r,
                   "Month #{i + 1}: rolling doesn't cap accrual, should be 2.333, got #{r.to_f}"
    end

    # The rolling window concept: after 12 months, accumulated = 27.996
    # If we continued to month 13, the window would drop month 1's accrual.
    # This is tracked by BalanceRule.available_balance.
    assert_in_delta 27.996, results.sum.to_f, 0.01
  end

  def test_balance_available_uses_rolling_window
    # Simulate 14 months of accrual, check that available_balance reflects rolling window
    periods = (1..14).map do |m|
      year = m <= 12 ? 2026 : 2027
      month = m <= 12 ? m : m - 12
      build_period(year, month)
    end

    history = []
    accumulated = BigDecimal('0')
    balance_rule = PROGRAM['balance_rule']

    periods.each do |_period|
      accrued = BigDecimal('2.333')
      accumulated += accrued
      history << accrued

      available = Factorial::BalanceRule.available_balance(accumulated, balance_rule, history)

      # After 12+ months, rolling window should only count last 12
      next unless history.size > 12

      expected_available = history.last(12).sum
      assert_in_delta expected_available.to_f, available.to_f, 0.001,
                      'Rolling window should only sum last 12 months'
    end
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #8 — UK: Rolling 12-month sick day entitlement',
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )
    fixture['note'] = 'balance_rule managed by runtime, not AST evaluator'

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain8_rolling_entitlement.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
