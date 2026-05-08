# frozen_string_literal: true

# Fake Factorial models — lightweight Structs that mirror the real ActiveRecord
# models in the Factorial backend. These let us develop and test the
# AccrualFactBuilder without Rails or a database.
#
# When porting to the backend, replace these Structs with the real AR models.

module Factorial
  Employee = Struct.new(
    :id,
    :hired_on,        # Date
    :full_name,       # String
    :country,         # String ("FR", "IT", "ES", "DE", ...)
    :children_count,  # Integer
    :gender,          # String ("male", "female", "other")
    keyword_init: true
  )

  Contract = Struct.new(
    :weekly_hours,    # Numeric (e.g. 35, 40, 20)
    :part_time,       # Boolean
    :fte_ratio,       # Float (0.0 - 1.0)
    :start_date,      # Date
    :end_date,        # Date (nil if current)
    keyword_init: true
  )

  Leave = Struct.new(
    :leave_type,      # String ("vacation", "sick_non_work_related", "parental", ...)
    :start_date,      # Date
    :end_date,        # Date
    :status,          # String ("approved", "pending", "rejected")
    keyword_init: true
  )

  Allowance = Struct.new(
    :id,
    :accrual_program, # Hash (the AST JSON, parsed)
    :days_type,       # String ("working_days", "natural_days", ...)
    :rounding,        # String ("half_day", "decimals", "quarters", "round_up")
    :company_country, # String
    :cycle_start,     # Date
    :cycle_end,       # Date
    keyword_init: true
  )
end
