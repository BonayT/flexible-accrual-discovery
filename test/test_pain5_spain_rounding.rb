# frozen_string_literal: true

require_relative 'test_helper'

# Pain #5 — Spain: Rounding to half-day precision
#
# Spanish labor: many companies round vacation accrual to half-days.
# Current Factorial uses fixed rounding modes. The AST `round` node
# handles this naturally with mode="nearest" step=0.5.
class TestPain5SpainRounding < Minitest::Test
  include TestHelpers

  # Program:
  # - Base: 1.833 days/month (22/12)
  # - Round to nearest 0.5
  PROGRAM = {
    'params' => { 'monthly_base' => 1.833 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'round',
        'value' => { 'type' => 'param', 'name' => 'monthly_base' },
        'mode' => 'nearest',
        'step' => 0.5
      }
    }
  }.freeze

  # Also test quarter-day rounding (step=0.25)
  PROGRAM_QUARTERS = {
    'params' => { 'monthly_base' => 1.833 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'round',
        'value' => { 'type' => 'param', 'name' => 'monthly_base' },
        'mode' => 'nearest',
        'step' => 0.25
      }
    }
  }.freeze

  def setup
    @employee = Factorial::Employee.new(
      id: 4,
      hired_on: Date.new(2022, 1, 10),
      full_name: 'Carlos García',
      country: 'ES',
      children_count: 1,
      gender: 'male'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 40,
      part_time: false,
      fte_ratio: 1.0,
      start_date: Date.new(2022, 1, 10),
      end_date: nil
    )
  end

  def test_half_day_rounding
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # 1.833 rounded to nearest 0.5 → 2.0
    results.each_with_index do |r, i|
      assert_equal BigDecimal('2'), r,
                   "Month #{i + 1}: 1.833 rounded to nearest 0.5 should be 2.0, got #{r.to_f}"
    end

    # Annual total: 12 * 2.0 = 24.0
    assert_equal BigDecimal('24'), results.sum
  end

  def test_quarter_day_rounding
    results = evaluate_year(
      program: PROGRAM_QUARTERS,
      employee: @employee,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # 1.833 rounded to nearest 0.25 → 1.75
    results.each_with_index do |r, i|
      assert_equal BigDecimal('1.75'), r,
                   "Month #{i + 1}: 1.833 rounded to nearest 0.25 should be 1.75, got #{r.to_f}"
    end
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #5 — Spain: Half-day rounding',
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain5_spain_rounding.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
