# frozen_string_literal: true

require "bigdecimal"
require "date"
require_relative "evaluator_ruby"

module AccrualPoc
  # Stateful balance pass that walks periods in order, applying:
  #   - accrual (from already-evaluated accrual rule values)
  #   - consumption (eval'd from balance.consumption per period)
  #   - expiration (per-bucket lifetime from balance.expiration.after_months)
  #   - carry-over at end_of_cycle (cap from balance.carry_over.max)
  #
  # Operates on a Ruby ledger of buckets: each accrual creates one bucket,
  # consumption draws from buckets in `consume_order`, and bucket expiration
  # / carry-over are deterministic.
  #
  # Required: program.period == "month" and scenario.cycle_anchor (for carry_over).
  # Daily / yearly cardinalities are not yet supported (refuse loudly).
  module BalanceEvaluator
    module_function

    DEFAULT_CONSUME_ORDER = "fifo"

    # Returns a hash:
    #   { enabled:, rows:, total_accrued:, total_consumed:, total_expired:,
    #     total_carryover_expired:, ending_balance: }
    #
    # rows[i] = {
    #   period:, opening_balance:, accrued:, consumed:, short:,
    #   expired_at_period:, expired_at_carryover:, carried_over:, closing_balance:,
    #   buckets_after: [ {units, accrued_at, expires_at, carried} ]
    # }
    def evaluate(program:, periods:, facts_for:, accrued_per_period:)
      balance = program["balance"]
      return { enabled: false, rows: [] } if balance.nil? || balance.empty?

      cardinality = program["period"] || "month"
      if cardinality != "month"
        raise "balance pass currently requires program.period == \"month\" (got #{cardinality.inspect})"
      end

      carry_cfg  = balance["carry_over"]
      expire_cfg = balance["expiration"]
      consume_node    = balance["consumption"]
      consume_order   = (balance["consume_order"] || DEFAULT_CONSUME_ORDER).to_s
      raise "balance.consume_order must be 'fifo' or 'lifo'" unless %w[fifo lifo].include?(consume_order)

      params_h = (program["params"] || {}).transform_keys(&:to_s)

      buckets = []
      rows = []
      total_accrued   = BigDecimal("0")
      total_consumed  = BigDecimal("0")
      total_expired   = BigDecimal("0")
      total_carry_exp = BigDecimal("0")

      periods.each_with_index do |p, idx|
        facts = facts_for.call(p)
        ctx   = EvaluatorRuby::Ctx.new(facts: facts, period: p, params: params_h, bindings: {})

        opening_balance = sum_buckets(buckets)

        # 1. Accrue
        accrued = to_bd(accrued_per_period[idx] || 0)
        if accrued.positive?
          expires_at = compute_expires_at(idx, expire_cfg, ctx, carried: false)
          buckets << { units: accrued, accrued_at: idx, expires_at: expires_at, carried: false }
        end
        total_accrued += accrued

        # 2. Consume
        consumption_request = consume_node ? to_bd(EvaluatorRuby.eval_node(consume_node, ctx)) : BigDecimal("0")
        consumed = consume_from_buckets!(buckets, consumption_request, consume_order)
        short = consumption_request - consumed
        total_consumed += consumed

        # 3. Expire by lifetime
        expired_at_period = BigDecimal("0")
        buckets.reject! do |b|
          if b[:expires_at] && b[:expires_at] <= idx
            expired_at_period += b[:units]
            true
          else
            false
          end
        end
        total_expired += expired_at_period

        # 4. Carry-over at end_of_cycle
        expired_at_carryover = BigDecimal("0")
        carried_over_units   = BigDecimal("0")
        last_of_cycle = p[:is_last_month_of_cycle] || (carry_cfg && p[:cycle_end].nil? && p[:month] == 12)
        if last_of_cycle && carry_cfg && carry_cfg["max"]
          cap = to_bd(eval_value(carry_cfg["max"], ctx))
          total_now = sum_buckets(buckets)
          if total_now > cap
            # Drop OLDEST first (carry-over keeps newest `cap` units, which
            # also have the longest remaining shelf-life under from:accrual_date).
            buckets.sort_by! { |b| [b[:accrued_at], b.object_id] }
            drop = total_now - cap
            while drop.positive? && (b = buckets.first)
              if b[:units] <= drop
                drop -= b[:units]
                expired_at_carryover += b[:units]
                buckets.shift
              else
                b[:units] -= drop
                expired_at_carryover += drop
                drop = BigDecimal("0")
              end
            end
          end
          carried_over_units = sum_buckets(buckets)
          # If expiration is anchored to the carry-over event, refresh expires_at.
          if expire_cfg && expire_cfg["from"] == "carry_over_date" && expire_cfg["after_months"]
            new_expiry = compute_expires_at(idx, expire_cfg, ctx, carried: true)
            buckets.each do |b|
              b[:expires_at] = new_expiry
              b[:carried] = true
            end
          end
        end
        total_carry_exp += expired_at_carryover

        closing_balance = sum_buckets(buckets)

        rows << {
          period: p,
          opening_balance: opening_balance,
          accrued: accrued,
          consumed: consumed,
          short: short,
          expired_at_period: expired_at_period,
          expired_at_carryover: expired_at_carryover,
          carried_over: carried_over_units,
          closing_balance: closing_balance,
          buckets_after: buckets.map { |b| b.dup }
        }
      end

      {
        enabled: true,
        rows: rows,
        total_accrued: total_accrued,
        total_consumed: total_consumed,
        total_expired: total_expired,
        total_carryover_expired: total_carry_exp,
        ending_balance: rows.last ? rows.last[:closing_balance] : BigDecimal("0")
      }
    end

    # ---- helpers ----

    def consume_from_buckets!(buckets, request, order)
      return BigDecimal("0") unless request.positive?
      ordered_indices =
        case order
        when "fifo" then (0...buckets.size).sort_by { |i| [buckets[i][:accrued_at], i] }
        when "lifo" then (0...buckets.size).sort_by { |i| [-buckets[i][:accrued_at], i] }
        end

      remaining = request
      consumed  = BigDecimal("0")
      ordered_indices.each do |i|
        break if remaining <= 0
        b = buckets[i]
        next if b.nil?
        taken = b[:units] < remaining ? b[:units] : remaining
        b[:units] -= taken
        consumed  += taken
        remaining -= taken
      end
      buckets.reject! { |b| b[:units] <= 0 }
      consumed
    end

    def compute_expires_at(idx, cfg, ctx, carried:)
      return nil unless cfg && cfg["after_months"]
      n = to_bd(eval_value(cfg["after_months"], ctx)).to_i
      raise "balance.expiration.after_months must be > 0" if n <= 0
      idx + n
    end

    # A balance config value can be a literal (number/string) or an AST node.
    def eval_value(spec, ctx)
      if spec.is_a?(Hash) && spec["type"]
        EvaluatorRuby.eval_node(spec, ctx)
      else
        spec
      end
    end

    def sum_buckets(buckets)
      buckets.inject(BigDecimal("0")) { |s, b| s + b[:units] }
    end

    def to_bd(v)
      return v if v.is_a?(BigDecimal)
      BigDecimal(v.to_s)
    end
  end
end
