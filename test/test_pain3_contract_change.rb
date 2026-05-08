# frozen_string_literal: true

require_relative 'test_helper'

# Pain #3 — Contract change mid-year: FT → PT (or vice versa)
#
# When an employee switches from full-time to part-time mid-year,
# accrual should change from the month of the new contract.
# Current Factorial requires manual policy reassignment.
#
# AST approach: the fact builder resolves the active contract per period,
# so the FTE ratio changes automatically. No AST change needed — same
# program as Pain #2, just different contract data.
class TestPain3ContractChange < Minitest::Test
  include TestHelpers

  # Same program as Pain #2
  PROGRAM = {
    'params' => { 'monthly_base' => 2.1667 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'mul',
        'operands' => [
          { 'type' => 'param', 'name' => 'monthly_base' },
          { 'type' => 'ref', 'path' => 'facts.contract.fte_ratio' }
        ]
      }
    }
  }.freeze

  def setup
    @employee = Factorial::Employee.new(
      id: 6,
      hired_on: Date.new(2021, 1, 15),
      full_name: 'Sophie Laurent',
      country: 'FR',
      children_count: 1,
      gender: 'female'
    )

    # Full-time Jan-Jun, then part-time from Jul
    @contracts = [
      Factorial::Contract.new(
        weekly_hours: 35, part_time: false, fte_ratio: 1.0,
        start_date: Date.new(2021, 1, 15),
        end_date: Date.new(2026, 6, 30)
      ),
      Factorial::Contract.new(
        weekly_hours: 21, part_time: true, fte_ratio: 0.6,
        start_date: Date.new(2026, 7, 1),
        end_date: nil
      )
    ]
  end

  def test_accrual_changes_with_contract
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: @contracts,
      leaves: [],
      year: 2026
    )

    # Jan-Jun: 2.1667 * 1.0 = 2.1667
    (0..5).each do |i|
      assert_in_delta 2.1667, results[i].to_f, 0.001,
                      "Month #{i + 1} (FT) should be ~2.1667, got #{results[i].to_f}"
    end

    # Jul-Dec: 2.1667 * 0.6 = 1.30002
    (6..11).each do |i|
      assert_in_delta 1.30002, results[i].to_f, 0.001,
                      "Month #{i + 1} (PT 60%) should be ~1.3, got #{results[i].to_f}"
    end

    # Annual total: 6 * 2.1667 + 6 * 1.30002 ≈ 20.80
    total = results.sum.to_f
    assert_in_delta 20.80, total, 0.1,
                    "Annual total should be ~20.80, got #{total}"
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #3 — Contract change: FT→PT mid-year',
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
