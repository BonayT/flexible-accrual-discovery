// evaluator.js — Port of AccrualPoc::EvaluatorRuby (~110 lines Ruby → JS)
// Pure, deterministic AST evaluator. No side effects.

export function evaluate(program, facts, period) {
  const params = program.params || {};
  const ctx = { facts, period, params, bindings: {} };
  const result = evalNode(program.rule, ctx);
  if (result === null || result === undefined) throw new Error("rule did not reach accrue");
  return result;
}

function withBinding(ctx, name, value) {
  return { ...ctx, bindings: { ...ctx.bindings, [name]: value } };
}

function evalNode(node, ctx) {
  switch (node.type) {
    case "const": return toNumOrKeep(node.value);
    case "ref":   return resolveRef(node.path, ctx);
    case "param": return toNumOrKeep(ctx.params[node.name]);

    case "lte": { const [a, b] = evalPair(node, ctx); return a != null && b != null ? a <= b : false; }
    case "lt":  { const [a, b] = evalPair(node, ctx); return a != null && b != null ? a <  b : false; }
    case "gte": { const [a, b] = evalPair(node, ctx); return a != null && b != null ? a >= b : false; }
    case "gt":  { const [a, b] = evalPair(node, ctx); return a != null && b != null ? a >  b : false; }
    case "eq":  return evalNode(node.left, ctx) === evalNode(node.right, ctx);
    case "neq": return evalNode(node.left, ctx) !== evalNode(node.right, ctx);
    case "and": return node.operands.every(o => evalNode(o, ctx));
    case "or":  return node.operands.some(o => evalNode(o, ctx));
    case "not": return !evalNode(node.operand, ctx);
    case "in": {
      const v = evalNode(node.value, ctx);
      return node.set.map(toNumOrKeep).includes(v);
    }
    case "exists": {
      const arr = evalNode(node.in, ctx);
      const binding = node.binding;
      return (Array.isArray(arr) ? arr : [arr]).some(
        elem => evalNode(node.where, withBinding(ctx, binding, elem))
      );
    }
    case "if":
      return evalNode(node.cond, ctx) ? evalNode(node.then, ctx) : evalNode(node.else, ctx);
    case "case": {
      const branch = node.branches.find(b => evalNode(b.when, ctx));
      return evalNode(branch ? branch.then : node.else, ctx);
    }
    case "add": return numOps(node, ctx).reduce((a, b) => a + b, 0);
    case "sub": { const ops = numOps(node, ctx); return ops.slice(1).reduce((a, b) => a - b, ops[0]); }
    case "mul": return numOps(node, ctx).reduce((a, b) => a * b, 1);
    case "div": { const ops = numOps(node, ctx); return ops.slice(1).reduce((a, b) => b === 0 ? 0 : a / b, ops[0]); }
    case "min": return Math.min(...numOps(node, ctx));
    case "max": return Math.max(...numOps(node, ctx));
    case "floor": return Math.floor(evalNode(node.value, ctx));
    case "round": {
      const step = node.step ? (typeof node.step === "object" ? evalNode(node.step, ctx) : node.step) : 1;
      const mode = typeof node.mode === "object" ? evalNode(node.mode, ctx) : (node.mode || "half_up");
      return roundValue(evalNode(node.value, ctx), mode, step);
    }
    case "accrue": return evalNode(node.amount, ctx);
    default: throw new Error(`unknown node type: ${node.type}`);
  }
}

function evalPair(node, ctx) {
  return [evalNode(node.left, ctx), evalNode(node.right, ctx)];
}

function numOps(node, ctx) {
  return node.operands.map(o => toNum(evalNode(o, ctx)));
}

function toNum(v) {
  return typeof v === "number" ? v : Number(v);
}

function toNumOrKeep(v) {
  if (typeof v === "number") return v;
  if (typeof v === "boolean" || typeof v === "string" || v === null || v === undefined) return v;
  return v;
}

function roundValue(value, mode, step) {
  const v = value / step;
  let rounded;
  switch (mode) {
    case "up":        rounded = Math.ceil(v); break;
    case "down":      rounded = Math.floor(v); break;
    case "nearest":
    case "half_up":   rounded = Math.round(v); break;
    case "half_even": rounded = Math.round(v); break; // simplified
    default: throw new Error(`unknown round mode: ${mode}`);
  }
  return rounded * step;
}

// --- Facts resolver (port of AccrualPoc::Facts) ---

function resolveRef(path, ctx) {
  const parts = path.split(".");
  const root = parts.shift();
  let base;
  if (root === "facts") base = ctx.facts;
  else if (root === "period") base = ctx.period;
  else if (root in ctx.bindings) base = ctx.bindings[root];
  else throw new Error(`unknown ref root: ${root}`);
  return walk(base, parts);
}

function walk(value, parts) {
  return parts.reduce((v, key) => {
    if (v == null) return null;
    // Date-derived fields
    const d = tryParseDate(v);
    if (d) {
      if (key === "day") return d.getUTCDate();
      if (key === "month") return d.getUTCMonth() + 1;
      if (key === "year") return d.getUTCFullYear();
      if (key === "year_month") return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
    }
    // Object/array access
    if (Array.isArray(v)) return v.map(e => access(e, key));
    return access(v, key);
  }, value);
}

function access(v, key) {
  if (v && typeof v === "object" && key in v) return v[key];
  return undefined;
}

function tryParseDate(v) {
  if (v instanceof Date) return v;
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v)) return new Date(v + "T00:00:00Z");
  return null;
}
