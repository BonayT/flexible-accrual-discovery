# frozen_string_literal: true

require_relative 'test_helper'

# Pain #4 — France: Sick leave reduces vacation accrual
#
# French labor code: employees who take extended sick leave (non-work-related)
# lose vacation accrual for those months. Currently impossible in Factorial
# because accrual ignores absence types.
#
# AST approach: use `exists` to check for sick absences in the period,
# then conditionally zero out accrual for that month.
class TestPain4FranceSickLeave < Minitest::Test
  include TestHelpers

  # The AST program:
  # - Base: 2.0833 days/month (25 days/year ÷ 12)
  # - If employee has an approved "sick_non_work_related" absence overlapping
  #   this month → accrue 0
  PROGRAM = {
    'params' => { 'monthly_base' => 2.0833 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'if',
        'cond' => {
          'type' => 'exists',
          'in' => { 'type' => 'ref', 'path' => 'facts.absences_in_period' },
          'binding' => 'absence',
          'where' => {
            'type' => 'eq',
            'left' => { 'type' => 'ref', 'path' => 'absence.type' },
            'right' => { 'type' => 'const', 'value' => 'sick_non_work_related' }
          }
        },
        'then' => { 'type' => 'const', 'value' => 0 },
        'else' => { 'type' => 'param', 'name' => 'monthly_base' }
      }
    }
  }.freeze

  def setup
    @employee = Factorial::Employee.new(
      id: 1,
      hired_on: Date.new(2020, 3, 15),
      full_name: 'Marie Dupont',
      country: 'FR',
      children_count: 0,
      gender: 'female'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 35,
      part_time: false,
      fte_ratio: 1.0,
      start_date: Date.new(2020, 3, 15),
      end_date: nil
    )

    # Sick leave in March and April 2026
    @leaves = [
      Factorial::Leave.new(
        leave_type: 'sick_non_work_related',
        start_date: Date.new(2026, 3, 5),
        end_date: Date.new(2026, 4, 20),
        status: 'approved'
      )
    ]
  end

  def test_healthy_months_accrue_normally
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # All 12 months should accrue 2.0833
    assert results.all? { |r| r == BigDecimal('2.0833') },
           "All months without sick leave should accrue 2.0833, got: #{results.map(&:to_f)}"
  end

  def test_sick_months_accrue_zero
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract],
      leaves: @leaves,
      year: 2026
    )

    # March (index 2) and April (index 3) should be 0
    assert_equal BigDecimal('0'), results[2], 'March (sick) should accrue 0'
    assert_equal BigDecimal('0'), results[3], 'April (sick) should accrue 0'

    # Other months should be normal
    [0, 1, 4, 5, 6, 7, 8, 9, 10, 11].each do |i|
      assert_equal BigDecimal('2.0833'), results[i],
                   "Month #{i + 1} should accrue 2.0833, got #{results[i].to_f}"
    end

    # Annual total: 10 * 2.0833 = 20.833 (instead of 25)
    total = results.sum
    assert_in_delta 20.833, total.to_f, 0.01,
                    "Annual total should be ~20.833 days, got #{total.to_f}"
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #4 — France: Sick leave reduces vacation accrual',
      program: PROGRAM,
      employee: @employee,
      contracts: [@contract],
      leaves: @leaves,
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain4_france_sick.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path), 'Fixture file should be created'
  end
end
