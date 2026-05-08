# frozen_string_literal: true

require 'date'
require 'bigdecimal'

# AccrualFactBuilder — the bridge between Factorial models and the AST evaluator.
#
# Takes fake (or real) Factorial models and produces the facts hash that the
# AST evaluator expects. This is the service that will be ported to the
# Factorial backend as Timeoff::AccrualFactBuilder.

module Factorial
  class AccrualFactBuilder
    # Builds the facts hash for a given employee + period.
    #
    # @param employee [Factorial::Employee]
    # @param contracts [Array<Factorial::Contract>]
    # @param leaves [Array<Factorial::Leave>]
    # @param period [Hash] period hash from PeriodIterator
    # @param cycle [Hash] optional cycle info (start/end dates for the full accrual cycle)
    # @return [Hash] facts hash consumable by the AST evaluator
    def facts_for(employee:, contracts:, leaves:, period:, cycle: nil)
      contract = active_contract(contracts, period)
      prev_contract = previous_contract(contracts, period)

      {
        # Employee facts
        hire_date: employee.hired_on,
        termination_date: employee.terminated_on,
        country: employee.country,
        children_count: employee.children_count,
        gender: employee.gender,
        is_terminated_in_period: terminated_in_period?(employee, period),
        worked_full_month: worked_full_month?(employee, period),

        # Tenure facts
        tenure_years_at_period_start: tenure_years(employee.hired_on, period[:start]),
        tenure_years_at_period_end: tenure_years(employee.hired_on, period[:end]),
        tenure_milestone_reached_in_cycle: tenure_milestone_in_cycle(employee.hired_on, cycle),

        # Contract facts
        contract: build_contract_facts(contract),
        previous_contract: build_contract_facts(prev_contract),

        # Absence facts
        absences_in_period: leaves_in_period(leaves, period),

        # Time worked facts
        days_worked_in_period: days_worked_in_period(leaves, period),
        working_days_in_period: period[:working_days],
        hours_worked_in_period: hours_worked_in_period(leaves, period, contract),
        reference_period_hours: reference_period_hours(contract, period),

        # Cycle facts (for pro-rata calculations)
        months_elapsed_in_cycle: months_elapsed_in_cycle(period, cycle),
        months_remaining_in_cycle: months_remaining_in_cycle(period, cycle),
        total_months_in_cycle: 12
      }
    end

    private

    def active_contract(contracts, period)
      contracts
        .select { |c| c.start_date <= period[:end] && (c.end_date.nil? || c.end_date >= period[:start]) }
        .max_by(&:start_date)
    end

    # The contract that was active before the current one in this period.
    def previous_contract(contracts, period)
      current = active_contract(contracts, period)
      return nil if current.nil?

      contracts
        .select { |c| c.end_date && c.end_date < current.start_date }
        .max_by(&:end_date)
    end

    def build_contract_facts(contract)
      return { weekly_hours: nil, days_per_week: 5, is_part_time: false, fte_ratio: 1.0 } if contract.nil?

      {
        weekly_hours: contract.weekly_hours,
        days_per_week: contract.days_per_week || 5,
        is_part_time: contract.part_time || false,
        fte_ratio: contract.fte_ratio || 1.0
      }
    end

    def tenure_years(hire_date, reference_date)
      return BigDecimal('0') if hire_date.nil? || reference_date.nil?
      return BigDecimal('0') if reference_date < hire_date

      (reference_date - hire_date).to_i / BigDecimal('365.25')
    end

    # Returns the tenure milestone (in years) reached during the current cycle, or nil.
    # E.g., if employee hits 5 years of tenure during this cycle, returns 5.
    def tenure_milestone_in_cycle(hire_date, cycle)
      return nil if hire_date.nil? || cycle.nil?

      cycle_start = cycle[:start]
      cycle_end = cycle[:end]

      tenure_at_start = ((cycle_start - hire_date).to_i / 365.25).floor
      tenure_at_end = ((cycle_end - hire_date).to_i / 365.25).floor

      # If tenure crossed a year boundary during the cycle, return the new milestone
      tenure_at_end > tenure_at_start ? tenure_at_end : nil
    end

    def terminated_in_period?(employee, period)
      return false if employee.terminated_on.nil?

      employee.terminated_on >= period[:start] && employee.terminated_on <= period[:end]
    end

    # Did the employee work at least one day in this period?
    # For Portugal: "full month not worked = 0"
    def worked_full_month?(employee, period)
      return false if employee.hired_on > period[:end]
      return false if employee.terminated_on && employee.terminated_on < period[:start]

      true
    end

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

    def days_worked_in_period(leaves, period)
      total_working = period[:working_days] || 22
      leave_days = leaves_in_period(leaves, period).sum do |l|
        leave_start = [l[:start], period[:start]].max
        leave_end = [l[:end], period[:end]].min
        (leave_start..leave_end).count { |d| d.wday.between?(1, 5) }
      end
      [total_working - leave_days, 0].max
    end

    def hours_worked_in_period(leaves, period, contract)
      return nil if contract.nil? || contract.weekly_hours.nil?

      days = days_worked_in_period(leaves, period)
      days_per_week = contract.days_per_week || 5
      daily_hours = contract.weekly_hours.to_f / days_per_week
      (days * daily_hours).round(2)
    end

    # Reference hours = what a full-time employee would work in this period.
    # Used for proportional hourly accrual: actual_hours / reference_hours.
    def reference_period_hours(contract, period)
      return nil if contract.nil?

      working_days = period[:working_days] || 22
      full_time_weekly = 40.0 # Standard full-time hours
      daily_hours = full_time_weekly / 5.0
      (working_days * daily_hours).round(2)
    end

    def months_elapsed_in_cycle(period, cycle)
      return 0 if cycle.nil?

      start_month = cycle[:start].month + (cycle[:start].year * 12)
      current_month = period[:start].month + (period[:start].year * 12)
      [current_month - start_month + 1, 1].max
    end

    def months_remaining_in_cycle(period, cycle)
      return 12 if cycle.nil?

      end_month = cycle[:end].month + (cycle[:end].year * 12)
      current_month = period[:start].month + (period[:start].year * 12)
      [end_month - current_month + 1, 0].max
    end
  end
end
