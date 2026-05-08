# frozen_string_literal: true

require_relative 'test_helper'

# Pain #6 — Accrual per days worked instead of hours worked
#
# Part-timers need vacation calculated proportionally by days worked per week.
# Formula: vacation days = (days_worked_per_week / 5) × 23 annual days
# System currently only supports full-day or hours-based, not days-per-week.
class TestPain6DaysWorked < Minitest::Test
  include TestHelpers

  # Program: (contract.days_per_week / 5) × (annual_days / 12)
  PROGRAM = {
    'params' => { 'annual_days' => 23, 'full_time_days_per_week' => 5 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'mul',
        'operands' => [
          {
            'type' => 'div',
            'operands' => [
              { 'type' => 'ref', 'path' => 'facts.contract.days_per_week' },
              { 'type' => 'param', 'name' => 'full_time_days_per_week' }
            ]
          },
          {
            'type' => 'div',
            'operands' => [
              { 'type' => 'param', 'name' => 'annual_days' },
              { 'type' => 'const', 'value' => 12 }
            ]
          }
        ]
      }
    }
  }.freeze

  def setup
    @employee = Factorial::Employee.new(
      id: 7, hired_on: Date.new(2023, 1, 1), terminated_on: nil,
      full_name: 'Emma Weber', country: 'DE', children_count: 0, gender: 'female'
    )

    @contract_5days = Factorial::Contract.new(
      weekly_hours: 40, days_per_week: 5, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2023, 1, 1), end_date: nil
    )

    @contract_3days = Factorial::Contract.new(
      weekly_hours: 24, days_per_week: 3, part_time: true, fte_ratio: 0.6,
      start_date: Date.new(2023, 1, 1), end_date: nil
    )

    @contract_4days = Factorial::Contract.new(
      weekly_hours: 32, days_per_week: 4, part_time: true, fte_ratio: 0.8,
      start_date: Date.new(2023, 1, 1), end_date: nil
    )
  end

  def test_full_time_5_days
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_5days],
      leaves: [],
      year: 2026
    )

    # (5/5) × (23/12) = 1.9167
    results.each_with_index do |r, i|
      assert_in_delta 1.9167, r.to_f, 0.001,
                      "Month #{i + 1}: 5-day FT should yield ~1.9167, got #{r.to_f}"
    end
    assert_in_delta 23.0, results.sum.to_f, 0.01
  end

  def test_part_time_3_days
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_3days],
      leaves: [],
      year: 2026
    )

    # (3/5) × (23/12) = 0.6 × 1.9167 = 1.15
    results.each_with_index do |r, i|
      assert_in_delta 1.15, r.to_f, 0.001,
                      "Month #{i + 1}: 3-day PT should yield ~1.15, got #{r.to_f}"
    end
    # Annual: 23 × 0.6 = 13.8
    assert_in_delta 13.8, results.sum.to_f, 0.01
  end

  def test_part_time_4_days
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_4days],
      leaves: [],
      year: 2026
    )

    # (4/5) × (23/12) = 0.8 × 1.9167 = 1.5333
    results.each_with_index do |r, i|
      assert_in_delta 1.5333, r.to_f, 0.001,
                      "Month #{i + 1}: 4-day PT should yield ~1.5333, got #{r.to_f}"
    end
    # Annual: 23 × 0.8 = 18.4
    assert_in_delta 18.4, results.sum.to_f, 0.01
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #6 — Accrual per days worked: 3-day PT = 60% of 23 days',
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract_3days],
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain6_days_worked.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
