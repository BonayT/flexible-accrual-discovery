# frozen_string_literal: true

require "date"

module AccrualPoc
  # Generates a sequence of monthly period hashes for a date range.
  # The shape matches what the evaluators expect.
  module PeriodIterator
    module_function

    # months("2026-01", "2026-12") -> [period hash, ...]
    # If `cycle_anchor` (Date) is given, attaches cycle_* metadata.
    def months(start_ym, end_ym, working_days: 22, cycle_anchor: nil)
      start_y, start_m = parse_ym(start_ym)
      end_y, end_m     = parse_ym(end_ym)

      periods = []
      y = start_y
      m = start_m
      loop do
        first = Date.new(y, m, 1)
        last  = Date.new(y, m, -1)
        p = {
          year: y,
          month: m,
          year_month: format("%04d-%02d", y, m),
          start: first,
          end: last,
          working_days: working_days,
          calendar_days: last.day
        }
        attach_cycle!(p, cycle_anchor) if cycle_anchor
        periods << p
        break if y == end_y && m == end_m
        m += 1
        if m > 12
          m = 1
          y += 1
        end
      end
      periods
    end

    def parse_ym(s)
      y, m = s.split("-").map(&:to_i)
      [y, m]
    end

    # years(2024, 2026) -> [period hash, ...] one per calendar year.
    # Each period has year-level metadata; `month` and `year_month` are nil.
    def years(start_y, end_y, working_days_per_year: 252, cycle_anchor: nil)
      (start_y..end_y).map do |y|
        first = Date.new(y, 1, 1)
        last  = Date.new(y, 12, 31)
        p = {
          year: y,
          month: nil,
          year_month: nil,
          year_str: y.to_s,
          start: first,
          end:   last,
          working_days:  working_days_per_year,
          calendar_days: (last - first).to_i + 1
        }
        # Yearly periods only carry cycle_index / cycle_start / cycle_end;
        # month_of_cycle / is_first/last_month_of_cycle don't apply.
        if cycle_anchor
          # Use period midpoint to pick a cycle (a calendar year usually
          # straddles two cycles when anchor is mid-year; we pick the cycle
          # the period STARTS in for determinism).
          attach_cycle!(p, cycle_anchor, monthly: false)
        end
        p
      end
    end

    # days("2026-03-01", "2026-03-31") -> [period hash, ...] one per calendar day.
    # Each period has both day-level and month-level metadata so existing
    # combinators (`period.year_month`, `period.month`, …) continue to work.
    def days(start_date, end_date, cycle_anchor: nil)
      s = start_date.is_a?(Date) ? start_date : Date.parse(start_date)
      e = end_date.is_a?(Date)   ? end_date   : Date.parse(end_date)
      raise "days(): start (#{s}) is after end (#{e})" if s > e

      (s..e).map do |d|
        last_of_month = Date.new(d.year, d.month, -1)
        p = {
          year: d.year,
          month: d.month,
          day: d.day,
          year_month: format("%04d-%02d", d.year, d.month),
          date: d,
          date_iso: d.iso8601,
          start: d,
          end:   d,
          day_of_week: d.wday,
          is_first_day_of_month: d.day == 1,
          is_last_day_of_month:  d == last_of_month,
          is_weekend:            (d.wday == 0 || d.wday == 6),
          working_days:  (d.wday.between?(1, 5) ? 1 : 0),
          calendar_days: 1
        }
        attach_cycle!(p, cycle_anchor) if cycle_anchor
        p
      end
    end

    # Dispatch helper. cardinality = "month" | "year" | "day".
    def for_program(cardinality, range, cycle_anchor: nil)
      case cardinality.to_s
      when "year"
        s, e = parse_year_range(range)
        years(s, e, cycle_anchor: cycle_anchor)
      when "day"
        s, e = parse_day_range(range)
        days(s, e, cycle_anchor: cycle_anchor)
      else
        s, e = parse_month_range(range)
        months(s, e, cycle_anchor: cycle_anchor)
      end
    end

    def parse_month_range(range)
      # Accept ["YYYY-MM","YYYY-MM"] or ["YYYY","YYYY"] (treat as Jan–Dec spans).
      range.map do |s|
        s.match?(/\A\d{4}\z/) ? "#{s}-01" : s
      end.then { |a| [a[0], range[1].match?(/\A\d{4}\z/) ? "#{range[1]}-12" : range[1]] }
    end

    def parse_year_range(range)
      range.map { |s| s.to_s[0, 4].to_i }
    end

    # Accepts ["YYYY-MM-DD","YYYY-MM-DD"], or a ["YYYY-MM","YYYY-MM"] pair
    # (expanded to first/last day of those months), or ["YYYY","YYYY"]
    # (expanded to Jan 1 / Dec 31).
    def parse_day_range(range)
      s = expand_to_date(range[0], at: :start)
      e = expand_to_date(range[1], at: :end)
      [s, e]
    end

    def expand_to_date(token, at:)
      t = token.to_s
      if t.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        Date.parse(t)
      elsif t.match?(/\A\d{4}-\d{2}\z/)
        y, m = t.split("-").map(&:to_i)
        at == :start ? Date.new(y, m, 1) : Date.new(y, m, -1)
      elsif t.match?(/\A\d{4}\z/)
        y = t.to_i
        at == :start ? Date.new(y, 1, 1) : Date.new(y, 12, 31)
      else
        raise "cannot parse range token: #{token.inspect}"
      end
    end

    # Annotate a monthly/daily period in-place with cycle_* metadata derived
    # from `anchor` (a Date). Cycles are 12 calendar months long, starting on
    # the first of the anchor's month-of-year, repeating yearly. Cycle 1 is
    # the cycle that starts on (anchor.year, anchor.month, 1).
    #
    # For periods strictly before cycle 1 (e.g. months before hire), cycle_index
    # is 0 or negative; consumers can guard with `period.cycle_index > 0`.
    def attach_cycle!(period, anchor, monthly: true)
      a_year  = anchor.year
      a_month = anchor.month
      ref     = period[:start] || Date.new(period[:year], period[:month] || 1, 1)

      # Number of months between cycle-1-start (a_year, a_month, 1) and ref.
      months_since_anchor = (ref.year - a_year) * 12 + (ref.month - a_month)
      cycle_index   = (months_since_anchor / 12) + 1
      month_of_cycle = (months_since_anchor % 12) + 1
      # Ruby's % keeps the sign of the divisor (positive), so month_of_cycle
      # is always 1..12 even when months_since_anchor is negative.

      cycle_start_year_offset = (cycle_index - 1)
      cycle_start = Date.new(a_year + cycle_start_year_offset, a_month, 1)
      cycle_end   = (cycle_start >> 12) - 1   # last day of month before next cycle start

      period[:cycle_anchor]      = anchor
      period[:cycle_index]       = cycle_index
      period[:cycle_start]       = cycle_start
      period[:cycle_end]         = cycle_end
      if monthly
        period[:month_of_cycle]          = month_of_cycle
        period[:is_first_month_of_cycle] = (month_of_cycle == 1)
        period[:is_last_month_of_cycle]  = (month_of_cycle == 12)
      end
    end
  end
end
