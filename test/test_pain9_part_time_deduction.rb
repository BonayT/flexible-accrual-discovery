# frozen_string_literal: true

require_relative 'test_helper'

# Pain #9 — Part-Time Time-Off Calculation
#
# Same as #6: if accrual is same as full-time, but deduction is proportional
# based on contracted hours vs full-time hours. In practice, many systems solve
# this at accrual time (accrue proportionally) so deduction stays 1:1.
#
# This test validates the pattern is the same as #2/#6 — no new AST capability
# needed, just different parameterization.
class TestPain9PartTimeDeduction < Minitest::Test
  include TestHelpers

  # Option A: Proportional accrual (same as pain #2 FTE approach)
  # Part-timer accrues less, deducts full days.
  PROGRAM_PROPORTIONAL_ACCRUAL = {
    'params' => { 'full_time_monthly' => 2.5 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'mul',
        'operands' => [
          { 'type' => 'param', 'name' => 'full_time_monthly' },
          { 'type' => 'ref', 'path' => 'facts.contract.fte_ratio' }
        ]
      }
    }
  }.freeze

  # Option B: Full accrual, proportional deduction
  # Part-timer accrues same as full-time. Deduction is handled separately.
  # This just validates the accrual side stays at full rate.
  PROGRAM_FULL_ACCRUAL = {
    'params' => { 'monthly_base' => 2.5 },
    'rule' => {
      'type' => 'accrue',
      'amount' => { 'type' => 'param', 'name' => 'monthly_base' }
    }
  }.freeze

  def setup
    @employee = Factorial::Employee.new(
      id: 10, hired_on: Date.new(2022, 1, 1), terminated_on: nil,
      full_name: 'Clara Hofmann', country: 'DE', children_count: 0, gender: 'female'
    )

    @contract_60pct = Factorial::Contract.new(
      weekly_hours: 24, days_per_week: 3, part_time: true, fte_ratio: 0.6,
      start_date: Date.new(2022, 1, 1), end_date: nil
    )
  end

  def test_proportional_accrual_60pct
    results = evaluate_year(
      program: PROGRAM_PROPORTIONAL_ACCRUAL,
      employee: @employee,
      contracts: [@contract_60pct],
      leaves: [],
      year: 2026
    )

    # 2.5 × 0.6 = 1.5
    results.each_with_index do |r, i|
      assert_equal BigDecimal('1.5'), r,
                   "Month #{i + 1}: 60% PT proportional accrual = 1.5, got #{r.to_f}"
    end
    assert_equal BigDecimal('18'), results.sum # 12 × 1.5
  end

  def test_full_accrual_regardless_of_contract
    results = evaluate_year(
      program: PROGRAM_FULL_ACCRUAL,
      employee: @employee,
      contracts: [@contract_60pct],
      leaves: [],
      year: 2026
    )

    # Full rate regardless
    results.each { |r| assert_equal BigDecimal('2.5'), r }
    assert_equal BigDecimal('30'), results.sum
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #9 — Part-time: proportional accrual at 60% FTE',
      program: PROGRAM_PROPORTIONAL_ACCRUAL,
      employee: @employee,
      contracts: [@contract_60pct],
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain9_part_time.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
