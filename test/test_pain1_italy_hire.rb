# frozen_string_literal: true

require_relative 'test_helper'

# Pain #1 — No accrual rule based on hire/termination date
#
# Italy: If hired before 15th, accrue full month; if hired on/after 16th, accrue 0 for that month.
# Portugal: If full month not worked, accrue 0 for the month; if full month worked, accrue 2 days.
# Also handles termination: if terminated mid-month, same logic applies.
class TestPain1HireTerminationDate < Minitest::Test
  include TestHelpers

  # Italy program:
  # - If period is before hire month → 0 (not yet employed)
  # - If period is hire month AND hired after 15th → 0
  # - Else → full monthly base
  PROGRAM_ITALY = {
    'params' => { 'monthly_base' => 2.1667 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'case',
        'branches' => [
          {
            # Period before hire → 0
            'when' => {
              'type' => 'lt',
              'left' => { 'type' => 'ref', 'path' => 'period.year_month' },
              'right' => { 'type' => 'ref', 'path' => 'facts.hire_date.year_month' }
            },
            'then' => { 'type' => 'const', 'value' => 0 }
          },
          {
            # Hire month + day > 15 → 0
            'when' => {
              'type' => 'and',
              'operands' => [
                { 'type' => 'eq',
                  'left' => { 'type' => 'ref', 'path' => 'period.year_month' },
                  'right' => { 'type' => 'ref', 'path' => 'facts.hire_date.year_month' } },
                { 'type' => 'gt',
                  'left' => { 'type' => 'ref', 'path' => 'facts.hire_date.day' },
                  'right' => { 'type' => 'const', 'value' => 15 } }
              ]
            },
            'then' => { 'type' => 'const', 'value' => 0 }
          }
        ],
        'else' => { 'type' => 'param', 'name' => 'monthly_base' }
      }
    }
  }.freeze

  # Portugal program: if employee didn't work full month → 0, else → 2 days
  # "worked_full_month" fact is false when hire/termination makes the month partial
  PROGRAM_PORTUGAL = {
    'params' => { 'monthly_base' => 2 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'if',
        'cond' => { 'type' => 'ref', 'path' => 'facts.worked_full_month' },
        'then' => { 'type' => 'param', 'name' => 'monthly_base' },
        'else' => { 'type' => 'const', 'value' => 0 }
      }
    }
  }.freeze

  def setup
    @employee_italy_early = Factorial::Employee.new(
      id: 1, hired_on: Date.new(2026, 3, 10), terminated_on: nil,
      full_name: 'Marco Rossi', country: 'IT', children_count: 0, gender: 'male'
    )

    @employee_italy_late = Factorial::Employee.new(
      id: 2, hired_on: Date.new(2026, 3, 20), terminated_on: nil,
      full_name: 'Luca Verdi', country: 'IT', children_count: 0, gender: 'male'
    )

    @employee_portugal_terminated = Factorial::Employee.new(
      id: 3, hired_on: Date.new(2024, 1, 10), terminated_on: Date.new(2026, 6, 15),
      full_name: 'João Silva', country: 'PT', children_count: 0, gender: 'male'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 40, days_per_week: 5, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2024, 1, 1), end_date: nil
    )
  end

  def test_italy_hired_before_15th_gets_full_month
    results = evaluate_year(
      program: PROGRAM_ITALY,
      employee: @employee_italy_early,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # Jan-Feb: before hire → 0
    assert_equal BigDecimal('0'), results[0], 'Jan (pre-hire) should be 0'
    assert_equal BigDecimal('0'), results[1], 'Feb (pre-hire) should be 0'
    # March (hire month, day=10 ≤ 15) → full accrual
    assert_equal BigDecimal('2.1667'), results[2], 'March should accrue full (hired on 10th)'
    # April onwards → full
    (3..11).each do |i|
      assert_equal BigDecimal('2.1667'), results[i],
                   "Month #{i + 1} should accrue full, got #{results[i].to_f}"
    end
  end

  def test_italy_hired_after_15th_gets_zero_for_hire_month
    results = evaluate_year(
      program: PROGRAM_ITALY,
      employee: @employee_italy_late,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # Jan-Feb: before hire → 0
    assert_equal BigDecimal('0'), results[0], 'Jan (pre-hire) should be 0'
    assert_equal BigDecimal('0'), results[1], 'Feb (pre-hire) should be 0'
    # March (hire month, day=20 > 15) → 0
    assert_equal BigDecimal('0'), results[2], 'March should be 0 (hired on 20th)'
    # April onwards → full
    (3..11).each do |i|
      assert_equal BigDecimal('2.1667'), results[i],
                   "Month #{i + 1} should be full, got #{results[i].to_f}"
    end
  end

  def test_portugal_terminated_employee_zero_after_termination
    results = evaluate_year(
      program: PROGRAM_PORTUGAL,
      employee: @employee_portugal_terminated,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # Jan-May: worked full month → 2
    (0..4).each do |i|
      assert_equal BigDecimal('2'), results[i],
                   "Month #{i + 1} should be 2 (worked full month)"
    end

    # June: terminated on 15th — still "worked" that month (started before period start)
    # Actually worked_full_month? returns true since hire < period_start and termination >= period_start
    assert_equal BigDecimal('2'), results[5], 'June (termination month) should be 2 (was active at month start)'

    # July onwards: terminated before period start → worked_full_month = false
    (6..11).each do |i|
      assert_equal BigDecimal('0'), results[i],
                   "Month #{i + 1} should be 0 (terminated)"
    end
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #1 — Italy: Hire date after 15th = 0 accrual for hire month',
      program: PROGRAM_ITALY,
      employee: @employee_italy_late,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain1_hire_termination.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
