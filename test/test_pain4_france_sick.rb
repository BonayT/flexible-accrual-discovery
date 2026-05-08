# frozen_string_literal: true

require_relative 'test_helper'

# Pain #4 — No rule to accrue differently during certain absences
#
# France: non-work-related sick leave → accrue at 80% rate (2 days/month instead of 2.5)
# DACH: similar rules exist for extended sick leave
# Currently impossible because accrual ignores absence types.
class TestPain4AbsenceTypeAccrual < Minitest::Test
  include TestHelpers

  # France program:
  # - Normal: 2.5 days/month (30/12)
  # - If sick_non_work_related in period → 80% rate = 2.0 days/month
  PROGRAM_FRANCE = {
    'params' => { 'full_rate' => 2.5, 'sick_rate' => 2.0 },
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
        'then' => { 'type' => 'param', 'name' => 'sick_rate' },
        'else' => { 'type' => 'param', 'name' => 'full_rate' }
      }
    }
  }.freeze

  # DACH program: extended sick (>6 weeks) → 0 accrual
  # Simplified: any sick_non_work_related in period → 0
  PROGRAM_DACH = {
    'params' => { 'full_rate' => 2.5 },
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
        'else' => { 'type' => 'param', 'name' => 'full_rate' }
      }
    }
  }.freeze

  def setup
    @employee_fr = Factorial::Employee.new(
      id: 1, hired_on: Date.new(2020, 3, 15), terminated_on: nil,
      full_name: 'Marie Dupont', country: 'FR', children_count: 0, gender: 'female'
    )

    @employee_de = Factorial::Employee.new(
      id: 2, hired_on: Date.new(2019, 1, 1), terminated_on: nil,
      full_name: 'Hans Schmidt', country: 'DE', children_count: 1, gender: 'male'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 35, days_per_week: 5, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2019, 1, 1), end_date: nil
    )

    # Sick leave March-April 2026
    @sick_leaves = [
      Factorial::Leave.new(
        leave_type: 'sick_non_work_related',
        start_date: Date.new(2026, 3, 5),
        end_date: Date.new(2026, 4, 20),
        status: 'approved'
      )
    ]
  end

  def test_france_sick_months_get_reduced_rate
    results = evaluate_year(
      program: PROGRAM_FRANCE,
      employee: @employee_fr,
      contracts: [@contract],
      leaves: @sick_leaves,
      year: 2026
    )

    # Healthy months: 2.5
    [0, 1, 4, 5, 6, 7, 8, 9, 10, 11].each do |i|
      assert_equal BigDecimal('2.5'), results[i],
                   "Month #{i + 1} (healthy) should be 2.5, got #{results[i].to_f}"
    end

    # Sick months (March, April): 2.0 (80% rate)
    assert_equal BigDecimal('2.0'), results[2], 'March (sick) should be 2.0 (80% rate)'
    assert_equal BigDecimal('2.0'), results[3], 'April (sick) should be 2.0 (80% rate)'

    # Annual total: 10×2.5 + 2×2.0 = 29.0 (instead of 30)
    assert_in_delta 29.0, results.sum.to_f, 0.01
  end

  def test_france_no_sick_gets_full_rate
    results = evaluate_year(
      program: PROGRAM_FRANCE,
      employee: @employee_fr,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    results.each { |r| assert_equal BigDecimal('2.5'), r }
    assert_equal BigDecimal('30'), results.sum
  end

  def test_dach_sick_months_get_zero
    results = evaluate_year(
      program: PROGRAM_DACH,
      employee: @employee_de,
      contracts: [@contract],
      leaves: @sick_leaves,
      year: 2026
    )

    assert_equal BigDecimal('0'), results[2], 'March (DACH sick) → 0'
    assert_equal BigDecimal('0'), results[3], 'April (DACH sick) → 0'
    assert_in_delta 25.0, results.sum.to_f, 0.01
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #4 — France: Sick leave reduces accrual to 80% rate',
      program: PROGRAM_FRANCE,
      employee: @employee_fr,
      contracts: [@contract],
      leaves: @sick_leaves,
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain4_absence_type.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
