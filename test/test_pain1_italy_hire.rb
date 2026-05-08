# frozen_string_literal: true

require_relative 'test_helper'

# Pain #1 — Italy: Hire date determines vacation entitlement
#
# Italian labor law: employees hired in H2 (July-Dec) get fewer vacation days
# in their first year. Currently Factorial can only prorate by full months.
#
# AST approach: use tenure_years + hire_date.month to determine base.
class TestPain1ItalyHireDate < Minitest::Test
  include TestHelpers

  # Program:
  # - If tenure < 1 year AND hire month > 6 → base = 1.333 days/month (16/12)
  # - Else → base = 2.1667 days/month (26/12, Italian standard)
  PROGRAM = {
    'params' => {
      'full_monthly' => 2.1667,
      'reduced_monthly' => 1.333
    },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'if',
        'cond' => {
          'type' => 'and',
          'operands' => [
            {
              'type' => 'lt',
              'left' => { 'type' => 'ref', 'path' => 'facts.tenure_years_at_period_start' },
              'right' => { 'type' => 'const', 'value' => 1 }
            },
            {
              'type' => 'gt',
              'left' => { 'type' => 'ref', 'path' => 'facts.hire_date.month' },
              'right' => { 'type' => 'const', 'value' => 6 }
            }
          ]
        },
        'then' => { 'type' => 'param', 'name' => 'reduced_monthly' },
        'else' => { 'type' => 'param', 'name' => 'full_monthly' }
      }
    }
  }.freeze

  def setup
    @employee_h2 = Factorial::Employee.new(
      id: 2,
      hired_on: Date.new(2025, 9, 1), # Hired Sept 2025 (H2)
      full_name: 'Marco Rossi',
      country: 'IT',
      children_count: 0,
      gender: 'male'
    )

    @employee_h1 = Factorial::Employee.new(
      id: 3,
      hired_on: Date.new(2025, 3, 1), # Hired March 2025 (H1)
      full_name: 'Giulia Bianchi',
      country: 'IT',
      children_count: 0,
      gender: 'female'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 40,
      part_time: false,
      fte_ratio: 1.0,
      start_date: Date.new(2025, 3, 1),
      end_date: nil
    )
  end

  def test_h2_hire_gets_reduced_rate_first_year
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee_h2,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # Tenure < 1 year for Jan-Sep 2026 (hired Sep 1 2025; 365/365.25 < 1).
    # Hire month = 9 > 6 → reduced rate for those months.
    # From Oct 2026 onwards, tenure >= 1 year → full rate.
    (0..8).each do |i| # Jan-Sep
      assert_equal BigDecimal('1.333'), results[i],
                   "Month #{i + 1} should use reduced rate (1.333), got #{results[i].to_f}"
    end

    (9..11).each do |i| # Oct-Dec
      assert_equal BigDecimal('2.1667'), results[i],
                   "Month #{i + 1} should use full rate (2.1667), got #{results[i].to_f}"
    end
  end

  def test_h1_hire_gets_full_rate
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee_h1,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # Hired March 2025, H1 → hire month = 3, not > 6
    # So always full rate regardless of tenure
    results.each_with_index do |r, i|
      assert_equal BigDecimal('2.1667'), r,
                   "Month #{i + 1} should use full rate (2.1667), got #{r.to_f}"
    end
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #1 — Italy: H2 hire gets reduced first-year accrual',
      program: PROGRAM,
      employee: @employee_h2,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain1_italy_hire.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
