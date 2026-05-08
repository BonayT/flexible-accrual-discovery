# frozen_string_literal: true

require_relative 'test_helper'

# Pain #2 — DACH (Germany/Austria/Switzerland): Hourly accrual for part-time
#
# DACH region: part-time employees accrue vacation proportional to their
# contracted hours (e.g., 20h/40h = 50% of full-time entitlement).
# Currently Factorial hardcodes day-based accrual.
#
# AST approach: multiply base by FTE ratio from contract facts.
class TestPain2DachHourly < Minitest::Test
  include TestHelpers

  # Program:
  # - Base: 2.5 days/month (30 statutory days / 12)
  # - Multiply by FTE ratio (from contract facts)
  PROGRAM = {
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
      id: 5,
      hired_on: Date.new(2023, 6, 1),
      full_name: 'Anna Müller',
      country: 'DE',
      children_count: 2,
      gender: 'female'
    )

    @contract_full = Factorial::Contract.new(
      weekly_hours: 40, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2023, 6, 1), end_date: nil
    )

    @contract_part = Factorial::Contract.new(
      weekly_hours: 20, part_time: true, fte_ratio: 0.5,
      start_date: Date.new(2023, 6, 1), end_date: nil
    )
  end

  def test_full_time_gets_full_accrual
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_full],
      leaves: [],
      year: 2026
    )

    results.each_with_index do |r, i|
      assert_equal BigDecimal('2.5'), r,
                   "Month #{i + 1}: full-time should get 2.5 days, got #{r.to_f}"
    end
  end

  def test_part_time_gets_proportional_accrual
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_part],
      leaves: [],
      year: 2026
    )

    # 2.5 * 0.5 = 1.25
    results.each_with_index do |r, i|
      assert_equal BigDecimal('1.25'), r,
                   "Month #{i + 1}: 50% part-time should get 1.25 days, got #{r.to_f}"
    end

    # Annual: 12 * 1.25 = 15 (vs 30 for full-time)
    assert_equal BigDecimal('15'), results.sum
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #2 — DACH: Part-time hourly accrual (50% FTE)',
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
