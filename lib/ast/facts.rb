# frozen_string_literal: true

require "date"
require "bigdecimal"

module AccrualPoc
  # Resolves dotted paths against (facts, period, bindings).
  # Supports sugar like `facts.hire_date.day`, `facts.hire_date.year_month`.
  module Facts
    module_function

    def resolve(path, ctx)
      parts = path.split(".")
      root  = parts.shift
      base  = case root
              when "facts"  then ctx.facts
              when "period" then ctx.period
              else
                raise "unknown ref root: #{root}" unless ctx.bindings.key?(root)
                ctx.bindings[root]
              end
      walk(base, parts)
    end

    def walk(value, parts)
      parts.reduce(value) do |v, key|
        next nil if v.nil?
        derived(v, key) || access(v, key)
      end
    end

    def access(value, key)
      case value
      when Hash    then value[key.to_sym] || value[key]
      when Array   then value.map { |e| access(e, key) }
      else
        sym = key.to_sym
        value.respond_to?(sym) ? value.public_send(sym) : nil
      end
    end

    def derived(value, key)
      return nil unless value.is_a?(Date) || value.is_a?(String) && date_string?(value)

      d = value.is_a?(Date) ? value : Date.parse(value)
      case key
      when "day"        then d.day
      when "month"      then d.month
      when "year"       then d.year
      when "year_month" then format("%04d-%02d", d.year, d.month)
      when "iso"        then d.iso8601
      end
    end

    def date_string?(s)
      !!(s =~ /\A\d{4}-\d{2}-\d{2}\z/)
    end
  end
end
