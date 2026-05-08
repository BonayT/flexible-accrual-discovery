# frozen_string_literal: true

require "date"

module AccrualPoc
  # Generates a sequence of monthly period hashes for a date range.
  # The shape matches what the evaluators expect.
  module PeriodIterator
    module_function

    # months("2026-01", "2026-12") -> [period hash, ...]
    def months(start_ym, end_ym, working_days: 22)
      start_y, start_m = parse_ym(start_ym)
      end_y, end_m     = parse_ym(end_ym)

      periods = []
      y = start_y
      m = start_m
      loop do
        first = Date.new(y, m, 1)
        last  = Date.new(y, m, -1)
        periods << {
          year: y,
          month: m,
          year_month: format("%04d-%02d", y, m),
          start: first,
          end: last,
          working_days: working_days,
          calendar_days: last.day
        }
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
    def years(start_y, end_y, working_days_per_year: 252)
      (start_y..end_y).map do |y|
        first = Date.new(y, 1, 1)
        last  = Date.new(y, 12, 31)
        {
          year: y,
          month: nil,
          year_month: nil,
          year_str: y.to_s,
          start: first,
          end:   last,
          working_days:  working_days_per_year,
          calendar_days: (last - first).to_i + 1
        }
      end
    end

    # days("2026-03-01", "2026-03-31") -> [period hash, ...] one per calendar day.
    # Each period has both day-level and month-level metadata so existing
    # combinators (`period.year_month`, `period.month`, …) continue to work.
    def days(start_date, end_date)
      s = start_date.is_a?(Date) ? start_date : Date.parse(start_date)
      e = end_date.is_a?(Date)   ? end_date   : Date.parse(end_date)
      raise "days(): start (#{s}) is after end (#{e})" if s > e

      (s..e).map do |d|
        last_of_month = Date.new(d.year, d.month, -1)
        {
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
      end
    end

    # Dispatch helper. cardinality = "month" | "year" | "day".
    def for_program(cardinality, range)
      case cardinality.to_s
      when "year"
        s, e = parse_year_range(range)
        years(s, e)
      when "day"
        s, e = parse_day_range(range)
        days(s, e)
      else
        months(*parse_month_range(range))
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
  end
end
