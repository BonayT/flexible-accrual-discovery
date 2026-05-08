# frozen_string_literal: true

require_relative 'test_helper'

# Pain #2 — No flexible accrual based on time worked vs full time
#
# DACH variable-hour employees: vacation = (actual hours / reference period hours) × statutory days
# The system currently only applies static entitlement rules.
class TestPain2DachHourly < Minitest::Test
  include TestHelpers

  # Program: (hours_worked_in_period / reference_period_hours) × (statutory_days / 12)
  # This gives monthly proportional accrual based on actual hours worked.
  PROGRAM = {
    'params' => { 'statutory_annual_days' => 30 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'mul',
        'operands' => [
          {
            'type' => 'div',
            'operands' => [
              { 'type' => 'ref', 'path' => 'facts.hours_worked_in_period' },
              { 'type' => 'ref', 'path' => 'facts.reference_period_hours' }
            ]
          },
          {
            'type' => 'div',
            'operands' => [
              { 'type' => 'param', 'name' => 'statutory_annual_days' },
              { 'type' => 'const', 'value' => 12 }
            ]
          }
        ]
      }
    }
  }.freeze

  # Simpler FTE-ratio based program (fallback for fixed-hour contracts)
  PROGRAM_FTE = {
    'params' => { 'monthly_base' => 2.5 },
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
      id: 5, hired_on: Date.new(2023, 6, 1), terminated_on: nil,
      full_name: 'Anna Müller', country: 'DE', children_count: 2, gender: 'female'
    )

    @contract_full = Factorial::Contract.new(
      weekly_hours: 40, days_per_week: 5, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2023, 6, 1), end_date: nil
    )

    @contract_part = Factorial::Contract.new(
      weekly_hours: 20, days_per_week: 5, part_time: true, fte_ratio: 0.5,
      start_date: Date.new(2023, 6, 1), end_date: nil
    )
  end

  def test_full_time_hours_based_accrual
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_full],
      leaves: [],
      year: 2026
    )

    # Full time: hours_worked = 22 * 8 = 176, reference = 22 * 8 = 176
    # ratio = 1.0, monthly = 30/12 = 2.5
    results.each_with_index do |r, i|
      assert_equal BigDecimal('2.5'), r,
                   "Month #{i + 1}: full-time hours-based should yield 2.5, got #{r.to_f}"
    end
  end

  def test_part_time_hours_based_accrual
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_part],
      leaves: [],
      year: 2026
    )

    # Part time 20h: hours_worked = 22 * (20/5) = 22 * 4 = 88, reference = 22 * 8 = 176
    # ratio = 0.5, monthly = 30/12 * 0.5 = 1.25
    results.each_with_index do |r, i|
      assert_equal BigDecimal('1.25'), r,
                   "Month #{i + 1}: part-time 20h should yield 1.25, got #{r.to_f}"
    end
  end

  def test_fte_ratio_simple_program
    results = evaluate_year(
      program: PROGRAM_FTE,
      employee: @employee,
      contracts: [@contract_part],
      leaves: [],
      year: 2026
    )

    results.each_with_index do |r, i|
      assert_equal BigDecimal('1.25'), r,
                   "Month #{i + 1}: FTE 0.5 × 2.5 = 1.25, got #{r.to_f}"
    end
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #2 — DACH: Hours-based proportional accrual (20h/40h)',
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_part],
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain2_dach_hourly.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
