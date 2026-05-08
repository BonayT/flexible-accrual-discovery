# frozen_string_literal: true

require 'minitest/autorun'
require 'bigdecimal'
require 'date'
require 'json'

# AST evaluator (from Romano's POC)
require_relative '../lib/ast/evaluator_ruby'
require_relative '../lib/ast/facts'
require_relative '../lib/ast/period_iterator'

# Factorial fake models + fact builder
require_relative '../lib/factorial/models'
require_relative '../lib/factorial/accrual_fact_builder'

module TestHelpers
  # Build a monthly period hash for a given year/month.
  # Mirrors what PeriodIterator.months produces.
  def build_period(year, month, working_days: 22)
    first = Date.new(year, month, 1)
    last = Date.new(year, month, -1)
    {
      year: year,
      month: month,
      year_month: format('%04d-%02d', year, month),
      start: first,
      end: last,
      working_days: working_days,
      calendar_days: last.day
    }
  end

  # Evaluate an AST program for each month in a year, using the fact builder.
  # Returns an array of 12 BigDecimal results.
  def evaluate_year(program:, employee:, contracts:, leaves:, year: 2026, cycle: nil)
    fact_builder = Factorial::AccrualFactBuilder.new
    cycle ||= { start: Date.new(year, 1, 1), end: Date.new(year, 12, 31) }

    (1..12).map do |month|
      period = build_period(year, month)
      facts = fact_builder.facts_for(
        employee: employee,
        contracts: contracts,
        leaves: leaves,
        period: period,
        cycle: cycle
      )
      AccrualPoc::EvaluatorRuby.evaluate(program, facts, period)
    end
  end

  # Generate a combined JSON fixture (compatible with Romano's POC playground)
  # from a program + scenario data.
  def generate_fixture(title:, program:, employee:, contracts:, leaves:, year: 2026)
    fact_builder = Factorial::AccrualFactBuilder.new
    period = build_period(year, 1) # sample period for base facts
    fact_builder.facts_for(
      employee: employee, contracts: contracts, leaves: [], period: period
    )

    # Build by_month overrides for months with leaves
    by_month = {}
    (1..12).each do |month|
      p = build_period(year, month)
      month_leaves = leaves.select { |l| l.start_date <= p[:end] && l.end_date >= p[:start] }
      next if month_leaves.empty?

      ym = format('%04d-%02d', year, month)
      by_month[ym] = {
        'absences_in_period' => month_leaves.map do |l|
          { 'type' => l.leave_type, 'start' => l.start_date.iso8601, 'end' => l.end_date.iso8601 }
        end
      }
    end

    {
      'title' => title,
      'program' => program,
      'scenario' => {
        'label' => employee.full_name,
        'range' => [format('%04d-01', year), format('%04d-12', year)],
        'facts' => {
          'hire_date' => employee.hired_on.iso8601,
          'country' => employee.country,
          'children_count' => employee.children_count,
          'gender' => employee.gender
        },
        'by_month' => by_month
      }
    }
  end
end
