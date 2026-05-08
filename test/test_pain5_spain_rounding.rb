# frozen_string_literal: true

require_relative 'test_helper'

# Pain #5 — Wrong rounding logic
#
# Spain: standard mathematical rounding to full days (<0.5 rounds down, ≥0.5 rounds up)
# Portugal: vacation days always round up to full days (e.g. 2.3 → 3)
# Current system rounds incorrectly (e.g. 2.3 → 3 when it should be 2 for Spain).
class TestPain5Rounding < Minitest::Test
  include TestHelpers

  # Spain: standard mathematical rounding to nearest full day (step=1)
  PROGRAM_SPAIN = {
    'params' => { 'monthly_base' => 1.833 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'round',
        'value' => { 'type' => 'param', 'name' => 'monthly_base' },
        'mode' => 'nearest',
        'step' => 1
      }
    }
  }.freeze

  # Spain half-day: round to nearest 0.5
  PROGRAM_SPAIN_HALF = {
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

  # Portugal: always round up to full days
  PROGRAM_PORTUGAL = {
    'params' => { 'monthly_base' => 2.3 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'round',
        'value' => { 'type' => 'param', 'name' => 'monthly_base' },
        'mode' => 'up',
        'step' => 1
      }
    }
  }.freeze

  def setup
    @employee_es = Factorial::Employee.new(
      id: 4, hired_on: Date.new(2022, 1, 10), terminated_on: nil,
      full_name: 'Carlos García', country: 'ES', children_count: 1, gender: 'male'
    )

    @employee_pt = Factorial::Employee.new(
      id: 5, hired_on: Date.new(2022, 1, 10), terminated_on: nil,
      full_name: 'Ana Oliveira', country: 'PT', children_count: 0, gender: 'female'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 40, days_per_week: 5, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2022, 1, 10), end_date: nil
    )
  end

  def test_spain_mathematical_rounding_full_day
    results = evaluate_year(
      program: PROGRAM_SPAIN,
      employee: @employee_es,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # 1.833 rounded to nearest 1 → 2 (standard math: 0.833 ≥ 0.5 → rounds up)
    results.each_with_index do |r, i|
      assert_equal BigDecimal('2'), r,
                   "Month #{i + 1}: 1.833 → nearest full day = 2, got #{r.to_f}"
    end
    assert_equal BigDecimal('24'), results.sum
  end

  def test_spain_half_day_rounding
    results = evaluate_year(
      program: PROGRAM_SPAIN_HALF,
      employee: @employee_es,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # 1.833 rounded to nearest 0.5 → 2.0 (1.833/0.5 = 3.666, round = 4, 4*0.5 = 2.0)
    results.each_with_index do |r, i|
      assert_equal BigDecimal('2'), r,
                   "Month #{i + 1}: 1.833 → nearest 0.5 = 2.0, got #{r.to_f}"
    end
  end

  def test_portugal_always_round_up
    results = evaluate_year(
      program: PROGRAM_PORTUGAL,
      employee: @employee_pt,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # 2.3 rounded up to next full day → 3
    results.each_with_index do |r, i|
      assert_equal BigDecimal('3'), r,
                   "Month #{i + 1}: 2.3 → round up = 3, got #{r.to_f}"
    end
    assert_equal BigDecimal('36'), results.sum
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #5 — Spain: Standard mathematical rounding to full days',
      program: PROGRAM_SPAIN,
      employee: @employee_es,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain5_rounding.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
