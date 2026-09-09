// The accrual engine, enough of it to put a number next to a number.
//
// Two things run here. `canonicalExpression` rebuilds the expression the engine
// generates for a counter today, so the simulator can show what production
// computes; an authored expression runs through the same facts, so the two
// numbers differ only by the rule. The facts mirror `AccrualFactBuilder`: same
// names, same meanings, same traps, including that `hire_date` is not the hire
// date.
//
// What is deliberately not modelled, because the simulator reports it as a wall
// instead of pretending otherwise: cadences other than all-at-once (no counter
// with one is ever assigned a program), carry-over, expiry, and the balance
// layer where the stored maximum is applied.

import { evaluate, referencedFacts, CelError } from './cel.js';

const DAY = 86400000;

const ENTITLEMENT_UNITS = 'double(allowance.holiday_allowance_in_cents) / 100.0';
const DAY_PRORATED_UNITS = `${ENTITLEMENT_UNITS} * active_days / cycle_days`;
const TENURE_TERM = 'tenure_adjustment_units * tenure_fraction';
const BASE_ACCRUAL =
  `((allowance.proration_type == 'proration_enabled' ` +
  `? ${DAY_PRORATED_UNITS} ` +
  `: ${ENTITLEMENT_UNITS}) ` +
  `+ ${TENURE_TERM})`;
const WINDOWED_ACCRUAL = `(${BASE_ACCRUAL} * availability_fraction)`;

// 19.8 is not binary-exact, so the double one step above it carries noise into
// the band's upper bound and would earn a quarter day the legacy tree never
// granted. Same slack the backend keeps, for the same reason.
const QUARTERS_UPPER_BOUND = '0.800000001';

const twoDecimals = (accrual) => `round.nearest(${accrual}, 0.01)`;

// Mirrors AccrualProgram.rounding_call_for. With the approximation on, both
// units collapse to round-to-nearest at the step. With it off they part company:
// days take the unequal three-zone band, hours advance to the next whole block.
function stepCall(accrual, { step, upper, unit, approximation }) {
  if (approximation) return `round.nearest(${accrual}, ${step})`;
  if (unit === 'hours') return `round.away_from_zero(${accrual}, ${step})`;
  return `round.banded(${accrual}, ${step}, 0.25, ${upper})`;
}

function roundingCall(counter, accrual) {
  const approximation = Boolean(counter.rounding_approximation);
  const unit = counter.allowance_type;

  switch (counter.rounding) {
    case 'round_up':
      return `${approximation ? 'round.nearest' : 'round.up'}(${twoDecimals(accrual)}, 1.0)`;
    case 'quarters':
      return stepCall(accrual, { step: '0.25', upper: QUARTERS_UPPER_BOUND, unit, approximation });
    case 'half_day':
      return stepCall(accrual, { step: '0.5', upper: '0.5', unit, approximation });
    default:
      return twoDecimals(accrual);
  }
}

// What the engine publishes for this counter today, byte for byte the shape the
// generator emits.
function canonicalExpression(counter) {
  return roundingCall(counter, WINDOWED_ACCRUAL);
}

// --- cycles ------------------------------------------------------------------

const iso = (date) => date.toISOString().slice(0, 10);
const addDays = (date, days) => new Date(date.getTime() + days * DAY);
const daysBetween = (from, to) => Math.round((to.getTime() - from.getTime()) / DAY) + 1;

function addMonths(date, months) {
  const target = new Date(date.getTime());
  const day = target.getUTCDate();
  target.setUTCDate(1);
  target.setUTCMonth(target.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(day, lastDay));
  return target;
}

// A counter's cycles over the window the simulator shows. `jan_dec` is the
// common case; an `employee_hired_date` cycle starts on the contract's own
// anniversary, which is the one place the cycle is per-employee.
function cyclesFor(counter, employee, { from, to }) {
  const length = counter.cycle_length || 12;
  const anchor =
    counter.timeoff_cycle === 'employee_hired_date'
      ? new Date(employee.contract_starts_on + 'T00:00:00Z')
      : new Date(Date.UTC(new Date(employee.contract_starts_on + 'T00:00:00Z').getUTCFullYear(), 0, 1));

  const cycles = [];
  let start = anchor;
  while (start <= to) {
    const regularEnd = addDays(addMonths(start, length), -1);
    if (regularEnd >= from) cycles.push({ regular_start: start, regular_end: regularEnd });
    start = addMonths(start, length);
    if (cycles.length > 40) break;
  }
  return cycles;
}

// The employee's active window inside a cycle, clipped by the contract and by a
// termination. `hire_date` is this window's start, which is why the fact is the
// contract start clipped to the cycle rather than the day they were hired.
function activeWindow(employee, cycle) {
  const contractStart = new Date(employee.contract_starts_on + 'T00:00:00Z');
  const contractEnd = employee.terminated_on ? new Date(employee.terminated_on + 'T00:00:00Z') : null;

  const start = contractStart > cycle.regular_start ? contractStart : cycle.regular_start;
  const end = contractEnd && contractEnd < cycle.regular_end ? contractEnd : cycle.regular_end;
  return { start, end, active: end >= start };
}

// --- tenure ------------------------------------------------------------------

// Which rung applies, by duration reached, and what it pays. The ladder is
// select-one: the highest rung reached wins, never the sum of the rungs below.
function rungFor(counter, tenureDate, at) {
  const rungs = [...(counter.tenure_periods || [])].sort(
    (a, b) => monthsOf(a) - monthsOf(b)
  );
  let reached = null;
  for (const rung of rungs) {
    if (addMonths(tenureDate, monthsOf(rung)) <= at) reached = rung;
  }
  return reached;
}

const monthsOf = (rung) => (rung.period_type === 'years' ? rung.period_length * 12 : rung.period_length);

// The bonus the engine hands CEL, already sized: day-prorated in Ruby when the
// counter prorates, which is why an expression that scales it again is refused.
function tenureAdjustmentUnits(counter, employee, cycle, window) {
  if (!counter.tenure_periods_enabled) return 0;
  const tenureDate = new Date(employee.tenure_date + 'T00:00:00Z');
  const rung = rungFor(counter, tenureDate, cycle.regular_end);
  if (!rung) return 0;

  const units = rung.adjustment_in_cents / 100;
  if (counter.proration_type !== 'proration_enabled') return units;
  const cycleDays = daysBetween(cycle.regular_start, cycle.regular_end);
  return units * (daysBetween(window.start, window.end) / cycleDays);
}

// 1.0 unless the counter pays the bonus from the milestone and the milestone
// falls inside this cycle, in which case only the part of the cycle after it.
function tenureFraction(counter, employee, cycle) {
  if (!counter.tenure_periods_enabled) return 1;
  if (counter.tenure_period_transition !== 'after_milestone') return 1;

  const tenureDate = new Date(employee.tenure_date + 'T00:00:00Z');
  const rung = rungFor(counter, tenureDate, cycle.regular_end);
  if (!rung) return 1;

  const milestone = addMonths(tenureDate, monthsOf(rung));
  if (milestone <= cycle.regular_start) return 1;
  const cycleDays = daysBetween(cycle.regular_start, cycle.regular_end);
  return daysBetween(milestone, cycle.regular_end) / cycleDays;
}

// --- facts --------------------------------------------------------------------

// Everything the evaluator binds, named as the fact builder names it. `contract`
// and `tenure` are the two entity inputs the pending pull requests add; they are
// bound here so the simulator can switch them off and show the same rule failing.
function buildFacts(counter, employee, cycle, { bindContract, bindTenure }) {
  const window = activeWindow(employee, cycle);
  const cycleDays = daysBetween(cycle.regular_start, cycle.regular_end);
  const activeDays = window.active ? daysBetween(window.start, window.end) : 0;

  const facts = {
    allowance: {
      __entity: 'timeoff.allowance',
      id: 1,
      allowance_type: counter.allowance_type,
      holiday_allowance_in_cents: counter.holiday_allowance_in_cents,
      proration_type: counter.proration_type,
      rounding: counter.rounding,
      rounding_approximation: Boolean(counter.rounding_approximation),
      source_units: counter.source_units || 'base_units',
      cycle_length: counter.cycle_length || 12,
      cycle_start: counter.cycle_start || null,
      timeoff_cycle: counter.timeoff_cycle || 'jan_dec',
      tenure_periods_enabled: Boolean(counter.tenure_periods_enabled),
      tenure_period_transition: counter.tenure_period_transition || null,
      timeoff_policy_id: 1
    },
    active_days: activeDays,
    cycle_days: cycleDays,
    tenure_adjustment_units: tenureAdjustmentUnits(counter, employee, cycle, window),
    tenure_fraction: tenureFraction(counter, employee, cycle),
    source_amount_units: 0,
    // Always 1.0 in production: no counter with a cadence is ever assigned a
    // program, so the windowing branch is unreachable outside a rake task.
    availability_fraction: 1,
    hire_date: window.start,
    cycle_start_date: cycle.regular_start,
    cycle_end_date: window.end,
    tenure_date: new Date(employee.tenure_date + 'T00:00:00Z')
  };

  if (bindContract) {
    // The hops the CEL environment expands from the bound contract. Only the
    // singular ones are modelled: a has_many binds as a list, and no expression
    // can fold one, so offering it would invite a rule that cannot evaluate.
    const day = (value) => (value ? new Date(value + 'T00:00:00Z') : null);

    const location = {
      __entity: 'locations.location',
      id: 1,
      name: employee.location_name || null,
      country: employee.location_country || employee.country || null,
      city: employee.location_city || null,
      state: null,
      postal_code: null,
      timezone: 'Europe/Madrid',
      main: true,
      company_id: 1
    };

    const legalEntity = {
      __entity: 'companies.legal_entity',
      id: 1,
      country: employee.legal_entity_country || employee.country || null,
      currency: 'EUR',
      legal_name: employee.legal_entity_name || null,
      main: true,
      company_id: 1
    };

    const terminationType = employee.termination_type
      ? {
          __entity: 'contracts.termination_type',
          id: 1,
          slug: employee.termination_type,
          description: employee.termination_type,
          termination_reason_type: null,
          is_deprecated: false,
          country: employee.country || null
        }
      : null;

    const parentContract = {
      __entity: 'contracts.contract',
      id: 1,
      employee_id: 1,
      company_id: 1,
      legal_entity_id: 1,
      country: employee.country || null,
      starts_on: day(employee.contract_starts_on),
      ends_on: day(employee.contract_ends_on || employee.terminated_on),
      is_discontinuous: false,
      contract_type_type: null,
      contract_type_id: null,
      legal_entity: legalEntity,
      status: { __entity: 'contracts.contract_status', id: 1, is_active: true, is_pausable: false, is_resumable: false }
    };

    const employeeEntity = {
      __entity: 'employees.employee',
      id: 1,
      access_id: 1,
      company_id: 1,
      first_name: 'Simulada',
      last_name: 'Empleada',
      full_name: 'Simulada Empleada',
      active: !employee.terminated_on,
      is_terminating: Boolean(employee.terminated_on),
      terminated_on: day(employee.terminated_on),
      location_id: 1,
      legal_entity_id: 1,
      manager_id: null,
      team_ids: [],
      default_location: location,
      company: { __entity: 'api_core.company', id: 1, name: 'Simulada SL', legal_name: 'Simulada SL' },
      terminationType,
      legalEntity: legalEntity
    };

    facts.contract = {
      __entity: 'contracts.contract_version',
      employee: employeeEntity,
      contract: parentContract,
      job_catalog_level: employee.job_level
        ? {
            __entity: 'job_catalog.level',
            id: 1,
            name: employee.job_level,
            role_name: employee.job_role || null,
            role_id: null,
            order: 1,
            is_default: false,
            archived: false,
            role: { __entity: 'job_catalog.role', id: 1, name: employee.job_role || null, description: null, archived: false, company_id: 1, competencies_ids: [], legal_entities_ids: [], supervisors_ids: [] }
          }
        : null,
      id: 1,
      employee_id: 1,
      company_id: 1,
      starts_on: new Date(employee.contract_starts_on + 'T00:00:00Z'),
      ends_on: employee.contract_ends_on ? new Date(employee.contract_ends_on + 'T00:00:00Z') : null,
      effective_on: new Date(employee.contract_starts_on + 'T00:00:00Z'),
      country: employee.country || null,
      job_title: employee.job_title || null,
      working_hours: employee.working_hours ?? null,
      working_hours_frequency: 'weekly',
      working_week_days: employee.working_week_days || null,
      // Nullable on purpose: NULL means full time, and Factor has no optional
      // inputs, so a rule reading it breaks for exactly that population.
      working_time_percentage_in_cents: employee.working_time_percentage_in_cents ?? null,
      has_trial_period: Boolean(employee.trial_period_ends_on),
      trial_period_ends_on: employee.trial_period_ends_on
        ? new Date(employee.trial_period_ends_on + 'T00:00:00Z')
        : null,
      salary_amount: employee.salary_amount ?? null,
      salary_frequency: null,
      is_reference: true,
      is_discontinuous: false,
      contract_status_is_active: true,
      status: 'active',
      has_payroll: false,
      contracts_contract_id: 1,
      job_catalog_level_id: null,
      job_catalog_role_id: null,
      job_catalog_tree_node_uuid: null,
      created_at: new Date(employee.contract_starts_on + 'T00:00:00Z'),
      updated_at: new Date(employee.contract_starts_on + 'T00:00:00Z')
    };
  }

  if (bindTenure) {
    const rung = rungFor(counter, facts.tenure_date, cycle.regular_end);
    facts.tenure = rung
      ? {
          __entity: 'timeoff.allowance_tenure_period',
          id: 1,
          timeoff_allowance_id: 1,
          period_type: rung.period_type,
          period_length: rung.period_length,
          max_cap_in_cents: rung.max_cap_in_cents ?? null,
          balance_type: rung.balance_type || 'fixed_balance'
        }
      : null;
  }

  return facts;
}

// --- running ------------------------------------------------------------------

function evaluateCycle(expression, facts, options = {}) {
  try {
    const { value, reads } = evaluate(expression, facts, options);
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return { error: `the expression returned ${JSON.stringify(value)} and the contract says float`, reads };
    }
    return { value, reads };
  } catch (error) {
    if (error instanceof CelError) return { error: error.message, hint: error.hint };
    throw error;
  }
}

// One row per cycle: what production computes today, what the authored rule
// computes, and the facts behind both so the card can show its work.
function simulate({ counter, employee, expression, from, to, bindContract = true, bindTenure = true, holidays = [] }) {
  const window = {
    from: new Date((from || `${new Date().getUTCFullYear()}-01-01`) + 'T00:00:00Z'),
    to: new Date((to || `${new Date().getUTCFullYear()}-12-31`) + 'T00:00:00Z')
  };

  const today = canonicalExpression(counter);

  return cyclesFor(counter, employee, window).map((cycle) => {
    const facts = buildFacts(counter, employee, cycle, { bindContract, bindTenure });
    const options = { holidays };
    return {
      label: `${cycle.regular_start.getUTCFullYear()}`,
      starts_on: iso(cycle.regular_start),
      ends_on: iso(cycle.regular_end),
      facts,
      today: evaluateCycle(today, facts, options),
      authored: expression ? evaluateCycle(expression, facts, options) : null
    };
  });
}

export {
  simulate,
  buildFacts,
  cyclesFor,
  canonicalExpression,
  roundingCall,
  referencedFacts,
  BASE_ACCRUAL,
  WINDOWED_ACCRUAL
};
