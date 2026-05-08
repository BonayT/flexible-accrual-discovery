# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/factorial/balance_rule'

# Pain #10 — No Maximum Limit on Available Overtime Balance
#
# If overtime balance exceeds 40 hours, stop accruing additional compensatory
# time off until balance is reduced. System does not allow setting a cap on
# accumulated overtime balance.
#
# AST approach: the program computes raw accrual, using `facts.accumulated_balance`
# to cap itself: accrue(min(raw, max(0, cap - accumulated_balance)))
# The runtime injects accumulated_balance each period via BalanceRule.
class TestPain10BalanceCap < Minitest::Test
  include TestHelpers

  # Program: accrue min(raw_monthly, max(0, cap - accumulated_balance))
  # This self-limits when approaching the cap.
  PROGRAM = {
    'balance_rule' => {
      'type' => 'capped',
      'cap' => 40
    },
    'params' => { 'monthly_overtime_accrual' => 5 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'min',
        'operands' => [
          { 'type' => 'param', 'name' => 'monthly_overtime_accrual' },
          {
            'type' => 'max',
            'operands' => [
              { 'type' => 'const', 'value' => 0 },
              {
                'type' => 'sub',
                'operands' => [
                  { 'type' => 'const', 'value' => 40 },
                  { 'type' => 'ref', 'path' => 'facts.accumulated_balance' }
                ]
              }
            ]
          }
        ]
      }
    }
  }.freeze

  def setup
    @employee = Factorial::Employee.new(
      id: 12, hired_on: Date.new(2020, 1, 1), terminated_on: nil,
      full_name: 'Martin Berger', country: 'DE', children_count: 0, gender: 'male'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 40, days_per_week: 5, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2020, 1, 1), end_date: nil
    )
  end

  def test_cap_stops_accrual_at_40
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

    # Month 1-8: accrue 5/month → accumulated grows from 0 to 40
    # Month 1: min(5, max(0, 40-0)) = min(5, 40) = 5 → acc = 5
    # Month 2: min(5, max(0, 40-5)) = min(5, 35) = 5 → acc = 10
    # ...
    # Month 8: min(5, max(0, 40-35)) = min(5, 5) = 5 → acc = 40
    # Month 9: min(5, max(0, 40-40)) = min(5, 0) = 0 → acc = 40
    # Month 10-12: 0
    (0..7).each do |i|
      assert_equal BigDecimal('5'), results[i],
                   "Month #{i + 1}: should accrue 5 (under cap), got #{results[i].to_f}"
    end

    (8..11).each do |i|
      assert_equal BigDecimal('0'), results[i],
                   "Month #{i + 1}: should accrue 0 (at cap), got #{results[i].to_f}"
    end

    # Total capped at 40
    assert_equal BigDecimal('40'), results.sum,
                 'Total accrual should be exactly 40 (the cap)'
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #10 — Overtime balance cap at 40h: stops accruing when reached',
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )
    fixture['note'] = 'balance_rule.capped: runtime injects accumulated_balance, AST self-limits'

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain10_balance_cap.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
