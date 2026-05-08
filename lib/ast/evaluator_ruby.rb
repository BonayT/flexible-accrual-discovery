# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"
require "date"
require_relative "facts"

module AccrualPoc
  # Walks an AST against (facts, period, params) and returns a BigDecimal.
  # The result is the value of the (single) `accrue` node reached.
  module EvaluatorRuby
    module_function

    def evaluate(program, facts, period)
      params = (program["params"] || {}).transform_keys(&:to_s)
      result = eval_node(program["rule"], Ctx.new(facts: facts, period: period, params: params, bindings: {}))
      raise "rule did not reach accrue" if result.nil?
      result
    end

    Ctx = Struct.new(:facts, :period, :params, :bindings, keyword_init: true) do
      def with_binding(name, value)
        Ctx.new(facts: facts, period: period, params: params, bindings: bindings.merge(name => value))
      end
    end

    # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
    def eval_node(node, ctx)
      case node["type"]
      when "const" then to_bd_or_keep(node["value"])
      when "ref"   then Facts.resolve(node["path"], ctx)
      when "param" then to_bd_or_keep(ctx.params.fetch(node["name"]))

      when "lte" then cmp(node, ctx) { |a, b| a.nil? || b.nil? ? false : a <= b }
      when "lt"  then cmp(node, ctx) { |a, b| a.nil? || b.nil? ? false : a <  b }
      when "gte" then cmp(node, ctx) { |a, b| a.nil? || b.nil? ? false : a >= b }
      when "gt"  then cmp(node, ctx) { |a, b| a.nil? || b.nil? ? false : a >  b }
      when "eq"  then eval_node(node["left"], ctx) == eval_node(node["right"], ctx)
      when "neq" then eval_node(node["left"], ctx) != eval_node(node["right"], ctx)
      when "and" then node["operands"].all? { |o| eval_node(o, ctx) }
      when "or"  then node["operands"].any? { |o| eval_node(o, ctx) }
      when "not" then !eval_node(node["operand"], ctx)
      when "in"
        v = eval_node(node["value"], ctx)
        node["set"].map { |c| to_bd_or_keep(c) }.include?(v)

      when "exists"
        arr = eval_node(node["in"], ctx)
        binding_name = node["binding"]
        Array(arr).any? { |elem| eval_node(node["where"], ctx.with_binding(binding_name, elem)) }

      when "if"
        eval_node(node["cond"], ctx) ? eval_node(node["then"], ctx) : eval_node(node["else"], ctx)
      when "case"
        branch = node["branches"].find { |b| eval_node(b["when"], ctx) }
        eval_node(branch ? branch["then"] : node["else"], ctx)

      when "add" then num_ops(node, ctx).reduce(BigDecimal("0"), :+)
      when "sub"
        ops = num_ops(node, ctx)
        ops[1..].reduce(ops[0], :-)
      when "mul" then num_ops(node, ctx).reduce(BigDecimal("1"), :*)
      when "div"
        ops = num_ops(node, ctx)
        ops[1..].reduce(ops[0]) { |acc, x| x.zero? ? BigDecimal("0") : acc / x }
      when "min" then num_ops(node, ctx).min
      when "max" then num_ops(node, ctx).max

      when "round" then round(eval_node(node["value"], ctx), node["mode"], node["step"] || 1)

      when "accrue" then eval_node(node["amount"], ctx)
      else raise "unknown node type: #{node['type'].inspect}"
      end
    end
    # rubocop:enable Metrics/MethodLength,Metrics/CyclomaticComplexity

    def cmp(node, ctx)
      a = eval_node(node["left"], ctx)
      b = eval_node(node["right"], ctx)
      yield a, b
    end

    def num_ops(node, ctx)
      node["operands"].map { |o| to_bd(eval_node(o, ctx)) }
    end

    def to_bd(v)
      v.is_a?(BigDecimal) ? v : BigDecimal(v.to_s)
    end

    def to_bd_or_keep(v)
      case v
      when Integer, Float then BigDecimal(v.to_s)
      when String, Date, TrueClass, FalseClass, NilClass, BigDecimal then v
      else v
      end
    end

    def round(value, mode, step)
      step = BigDecimal(step.to_s)
      v    = BigDecimal(value.to_s) / step
      rounded = case mode
                when "up"        then v.ceil
                when "down"      then v.floor
                when "nearest", "half_up" then v.round(0, BigDecimal::ROUND_HALF_UP)
                when "half_even" then v.round(0, BigDecimal::ROUND_HALF_EVEN)
                else raise "unknown round mode: #{mode}"
                end
      rounded * step
    end
  end
end
