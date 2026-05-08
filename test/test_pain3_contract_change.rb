# frozen_string_literal: true

require_relative 'test_helper'

# Pain #3 — Accrual rules cannot handle changes of full to part time
#
# If employee changes 40h to 20h in June:
#   (40h entitlement × 6/12) + (20h entitlement × 6/12)
# The system should auto-adjust proportionally to mid-year contract hour changes.
#
# AST approach: the fact builder resolves the active contract per period,
# so from month of change onwards, the FTE ratio / hours change automatically.
# The annual total is the sum of monthly accruals with different contracts.
class TestPain3ContractChange < Minitest::Test
  include TestHelpers

  # Program: monthly_base × (contract.weekly_hours / full_time_hours)
  # This auto-adapts when contract changes.
  PROGRAM = {
    'params' => { 'statutory_annual_days' => 26, 'full_time_hours' => 40 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'mul',
        'operands' => [
          {
            'type' => 'div',
            'operands' => [
              { 'type' => 'param', 'name' => 'statutory_annual_days' },
              { 'type' => 'const', 'value' => 12 }
            ]
          },
          {
            'type' => 'div',
            'operands' => [
              { 'type' => 'ref', 'path' => 'facts.contract.weekly_hours' },
              { 'type' => 'param', 'name' => 'full_time_hours' }
            ]
          }
        ]
      }
    }
  }.freeze

  def setup
    @employee = Factorial::Employee.new(
      id: 6, hired_on: Date.new(2021, 1, 15), terminated_on: nil,
      full_name: 'Sophie Laurent', country: 'FR', children_count: 1, gender: 'female'
    )

    # Full-time Jan-Jun (40h), then part-time Jul-Dec (20h)
    @contracts = [
      Factorial::Contract.new(
        weekly_hours: 40, days_per_week: 5, part_time: false, fte_ratio: 1.0,
        start_date: Date.new(2021, 1, 15), end_date: Date.new(2026, 6, 30)
      ),
      Factorial::Contract.new(
        weekly_hours: 20, days_per_week: 5, part_time: true, fte_ratio: 0.5,
        start_date: Date.new(2026, 7, 1), end_date: nil
      )
    ]
  end

  def test_accrual_changes_with_contract_hours
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: @contracts,
      leaves: [],
      year: 2026
    )

    # Jan-Jun: (26/12) × (40/40) = 2.1667
    (0..5).each do |i|
      assert_in_delta 2.1667, results[i].to_f, 0.001,
                      "Month #{i + 1} (40h FT) should be ~2.1667, got #{results[i].to_f}"
    end

    # Jul-Dec: (26/12) × (20/40) = 1.0833
    (6..11).each do |i|
      assert_in_delta 1.0833, results[i].to_f, 0.001,
                      "Month #{i + 1} (20h PT) should be ~1.0833, got #{results[i].to_f}"
    end

    # Annual total: 6×2.1667 + 6×1.0833 = 13.0 + 6.5 = 19.5
    total = results.sum.to_f
    assert_in_delta 19.5, total, 0.1,
                    "Annual total should be ~19.5 (vs 26 full-time), got #{total}"
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #3 — Contract change 40h→20h mid-year: auto pro-rata',
      program: PROGRAM,
      employee: @employee,
      contracts: @contracts,
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain3_contract_change.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
