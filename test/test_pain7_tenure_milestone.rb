# frozen_string_literal: true

require_relative 'test_helper'

# Pain #7 — Not possible to start accruing at tenure date
#
# Italy: If 5-year seniority reached in June, grant proportional extra:
#   extra_days × remaining_months / 12
# When employee reaches seniority mid-cycle, system grants full extra amount
# instead of pro-rating for the remaining months.
class TestPain7TenureMilestone < Minitest::Test
  include TestHelpers

  # Program with tenure-based case:
  # - Base: 2.1667 days/month (26/12)
  # - If tenure >= 10 years: +0.333/month (4 extra days/year)
  # - If tenure >= 5 years: +0.167/month (2 extra days/year)
  # The extra kicks in from the month tenure is reached.
  PROGRAM = {
    'params' => { 'base_monthly' => 2.1667 },
    'rule' => {
      'type' => 'accrue',
      'amount' => {
        'type' => 'add',
        'operands' => [
          { 'type' => 'param', 'name' => 'base_monthly' },
          {
            'type' => 'case',
            'branches' => [
              {
                'when' => {
                  'type' => 'gte',
                  'left' => { 'type' => 'ref', 'path' => 'facts.tenure_years_at_period_end' },
                  'right' => { 'type' => 'const', 'value' => 10 }
                },
                'then' => { 'type' => 'const', 'value' => 0.333 }
              },
              {
                'when' => {
                  'type' => 'gte',
                  'left' => { 'type' => 'ref', 'path' => 'facts.tenure_years_at_period_end' },
                  'right' => { 'type' => 'const', 'value' => 5 }
                },
                'then' => { 'type' => 'const', 'value' => 0.167 }
              }
            ],
            'else' => { 'type' => 'const', 'value' => 0 }
          }
        ]
      }
    }
  }.freeze

  def setup
    # Employee hits 5 years in June 2026 (hired June 15, 2021)
    @employee_5yr = Factorial::Employee.new(
      id: 8, hired_on: Date.new(2021, 6, 15), terminated_on: nil,
      full_name: 'Giuseppe Marino', country: 'IT', children_count: 0, gender: 'male'
    )

    # Employee already has 10+ years
    @employee_10yr = Factorial::Employee.new(
      id: 9, hired_on: Date.new(2015, 1, 1), terminated_on: nil,
      full_name: 'Francesca Ricci', country: 'IT', children_count: 2, gender: 'female'
    )

    @contract = Factorial::Contract.new(
      weekly_hours: 40, days_per_week: 5, part_time: false, fte_ratio: 1.0,
      start_date: Date.new(2015, 1, 1), end_date: nil
    )
  end

  def test_tenure_milestone_mid_year
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee_5yr,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # Jan-May: tenure < 5 → base only (2.1667)
    (0..4).each do |i|
      assert_in_delta 2.1667, results[i].to_f, 0.001,
                      "Month #{i + 1} (tenure < 5yr) should be base 2.1667, got #{results[i].to_f}"
    end

    # June onwards: tenure reaches 5yr at end of June (hired June 15, 2021)
    # tenure_at_period_end for June = (2026-06-30 - 2021-06-15) = 1841 days / 365.25 = 5.038 → ≥ 5
    (5..11).each do |i|
      assert_in_delta 2.3337, results[i].to_f, 0.001,
                      "Month #{i + 1} (tenure ≥ 5yr) should be 2.1667 + 0.167 = 2.3337, got #{results[i].to_f}"
    end

    # Annual: 5×2.1667 + 7×2.3337 = 10.8335 + 16.3359 = 27.17
    total = results.sum.to_f
    assert_in_delta 27.17, total, 0.1
  end

  def test_10_year_veteran_gets_full_extra
    results = evaluate_year(
      program: PROGRAM,
      employee: @employee_10yr,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    # All months: tenure ≥ 10 → 2.1667 + 0.333 = 2.4997
    results.each_with_index do |r, i|
      assert_in_delta 2.4997, r.to_f, 0.001,
                      "Month #{i + 1} (10yr vet) should be ~2.5, got #{r.to_f}"
    end
  end

  def test_generates_fixture
    fixture = generate_fixture(
      title: 'Pain #7 — Italy: 5-year tenure milestone grants extra accrual from June',
      program: PROGRAM,
      employee: @employee_5yr,
      contracts: [@contract],
      leaves: [],
      year: 2026
    )

    path = File.join(__dir__, '..', 'fixtures', 'pains', 'pain7_tenure_milestone.json')
    File.write(path, JSON.pretty_generate(fixture))
    assert File.exist?(path)
  end
end
