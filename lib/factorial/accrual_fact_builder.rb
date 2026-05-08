# frozen_string_literal: true

require 'date'
require 'bigdecimal'

# AccrualFactBuilder — the bridge between Factorial models and the AST evaluator.
#
# Takes fake (or real) Factorial models and produces the facts hash that the
# AST evaluator expects. This is the service that will be ported to the
# Factorial backend as Timeoff::AccrualFactBuilder.
#
# In production, replace the Struct-based inputs with ActiveRecord models and
# add real DB queries for leaves, contracts, etc.

module Factorial
  class AccrualFactBuilder
    # Builds the facts hash for a given employee + period.
    #
    # @param employee [Factorial::Employee]
    # @param contracts [Array<Factorial::Contract>]
    # @param leaves [Array<Factorial::Leave>]
    # @param period [Hash] period hash from PeriodIterator (keys: :year, :month, :start, :end, etc.)
    # @return [Hash] facts hash consumable by the AST evaluator
    def facts_for(employee:, contracts:, leaves:, period:)
      contract = active_contract(contracts, period)

      {
        hire_date: employee.hired_on,
        country: employee.country,
        children_count: employee.children_count,
        gender: employee.gender,
        tenure_years_at_period_start: tenure_years(employee.hired_on, period[:start]),
        tenure_years_at_period_end: tenure_years(employee.hired_on, period[:end]),
        contract: build_contract_facts(contract),
        absences_in_period: leaves_in_period(leaves, period),
        days_worked_in_period: days_worked_in_period(leaves, period),
        working_days_in_period: period[:working_days],
        hours_worked_in_period: hours_worked_in_period(leaves, period, contract)
      }
    end

    private

    # Find the contract active during this period.
    # If multiple contracts overlap, pick the one whose start_date is latest
    # but still <= period[:end].
    def active_contract(contracts, period)
      contracts
        .select { |c| c.start_date <= period[:end] && (c.end_date.nil? || c.end_date >= period[:start]) }
        .max_by(&:start_date)
    end

    def build_contract_facts(contract)
      return { weekly_hours: nil, is_part_time: false, fte_ratio: 1.0 } if contract.nil?

      {
        weekly_hours: contract.weekly_hours,
        is_part_time: contract.part_time || false,
        fte_ratio: contract.fte_ratio || 1.0
      }
    end

    # Fractional years of tenure at a reference date.
    def tenure_years(hire_date, reference_date)
      return BigDecimal('0') if hire_date.nil? || reference_date.nil?
      return BigDecimal('0') if reference_date < hire_date

      (reference_date - hire_date).to_i / BigDecimal('365.25')
    end

    # Returns an array of leave hashes that overlap with the period.
    # Format matches what the AST expects for `exists` iteration.
    def leaves_in_period(leaves, period)
      leaves
        .select { |l| l.status != 'rejected' }
        .select { |l| l.start_date <= period[:end] && l.end_date >= period[:start] }
        .map do |l|
          {
            type: l.leave_type,
            start: l.start_date,
            end: l.end_date
          }
        end
    end

    # Simplified: working days in period minus leave days.
    # In production this would use WorkScheduleMuncher, shift management, etc.
    def days_worked_in_period(leaves, period)
      total_working = period[:working_days] || 22
      leave_days = leaves_in_period(leaves, period).sum do |l|
        leave_start = [l[:start], period[:start]].max
        leave_end = [l[:end], period[:end]].min
        # Simple: count weekdays in the overlap
        (leave_start..leave_end).count { |d| d.wday.between?(1, 5) }
      end
      [total_working - leave_days, 0].max
    end

    # Simplified: hours worked based on contract hours and days worked.
    # In production this would come from Time Tracking.
    def hours_worked_in_period(leaves, period, contract)
      return nil if contract.nil? || contract.weekly_hours.nil?

      days = days_worked_in_period(leaves, period)
      daily_hours = contract.weekly_hours / 5.0
      (days * daily_hours).round(2)
    end
  end
end
