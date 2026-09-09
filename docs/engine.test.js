// The engine, checked against what the backend would compute for the same
// counter. The rounding strings are pinned separately against the Ruby emitter
// (see bin/dump_rounding_forms.rb) because a changed digit there reclassifies a
// real counter as authored.
//
//   node docs/engine.test.js

import { simulate, canonicalExpression, buildFacts, cyclesFor } from './engine.js';

let passed = 0;
const failures = [];

function check(name, fn) {
  try {
    fn();
    passed += 1;
  } catch (error) {
    failures.push({ name, message: error.message });
  }
}

function eq(actual, expected, note) {
  const same = typeof expected === 'number' && typeof actual === 'number'
    ? Math.abs(actual - expected) < 1e-9
    : actual === expected;
  if (!same) throw new Error(`${note || ''} esperaba ${JSON.stringify(expected)}, obtuve ${JSON.stringify(actual)}`);
}

const counter = (overrides = {}) => ({
  allowance_type: 'days',
  holiday_allowance_in_cents: 2200,
  proration_type: 'proration_disabled',
  rounding: 'decimals',
  rounding_approximation: false,
  timeoff_cycle: 'jan_dec',
  cycle_length: 12,
  tenure_periods_enabled: false,
  ...overrides
});

const employee = (overrides = {}) => ({
  contract_starts_on: '2019-06-01',
  terminated_on: null,
  tenure_date: '2019-06-01',
  working_time_percentage_in_cents: 10000,
  ...overrides
});

const oneCycle = (options) => simulate({ from: '2026-01-01', to: '2026-12-31', ...options })[0];

// --- the emitted rounding ------------------------------------------------------

check('decimals emits two decimals', () =>
  eq(canonicalExpression(counter()), 'round.nearest((((allowance.proration_type == \'proration_enabled\' ? double(allowance.holiday_allowance_in_cents) / 100.0 * active_days / cycle_days : double(allowance.holiday_allowance_in_cents) / 100.0) + tenure_adjustment_units * tenure_fraction) * availability_fraction), 0.01)'));

check('round_up ceils the two-decimal body', () =>
  eq(canonicalExpression(counter({ rounding: 'round_up' })).startsWith('round.up(round.nearest('), true));

check('round_up with the approximation rounds to nearest instead', () =>
  eq(canonicalExpression(counter({ rounding: 'round_up', rounding_approximation: true })).startsWith('round.nearest(round.nearest('), true));

check('half_day on days takes the three-zone band', () =>
  eq(canonicalExpression(counter({ rounding: 'half_day' })).startsWith('round.banded('), true));

check('half_day on hours advances to the next block', () =>
  eq(canonicalExpression(counter({ rounding: 'half_day', allowance_type: 'hours' })).startsWith('round.away_from_zero('), true));

check('quarters keeps the 0.800000001 slack', () =>
  eq(canonicalExpression(counter({ rounding: 'quarters' })).includes('0.800000001'), true));

check('the approximation collapses both units to nearest', () =>
  eq(canonicalExpression(counter({ rounding: 'quarters', allowance_type: 'hours', rounding_approximation: true })).startsWith('round.nearest('), true));

// --- what production computes today --------------------------------------------

check('a full year with no proration pays the entitlement', () => {
  const row = oneCycle({ counter: counter(), employee: employee() });
  eq(row.today.value, 22);
});

check('a mid-year hire with proration is docked', () => {
  const row = oneCycle({
    counter: counter({ proration_type: 'proration_enabled' }),
    employee: employee({ contract_starts_on: '2026-07-01' })
  });
  // 184 active days of 365: 22 * 184/365 = 11.09
  eq(row.facts.active_days, 184);
  eq(row.today.value, 11.09);
});

check('a mid-year hire without proration still pays the whole entitlement', () => {
  const row = oneCycle({
    counter: counter(),
    employee: employee({ contract_starts_on: '2026-07-01' })
  });
  eq(row.today.value, 22);
});

check('a leaver is clipped at the termination date', () => {
  const row = oneCycle({
    counter: counter({ proration_type: 'proration_enabled' }),
    employee: employee({ terminated_on: '2026-06-30' })
  });
  eq(row.facts.active_days, 181);
});

check('hire_date is the clipped start, not the day they were hired', () => {
  const row = oneCycle({ counter: counter(), employee: employee({ contract_starts_on: '2019-06-01' }) });
  eq(row.facts.hire_date.toISOString().slice(0, 10), '2026-01-01');
});

check('a mid-cycle joiner does have their real start as hire_date', () => {
  const row = oneCycle({ counter: counter(), employee: employee({ contract_starts_on: '2026-03-15' }) });
  eq(row.facts.hire_date.toISOString().slice(0, 10), '2026-03-15');
});

// --- the tenure ladder ----------------------------------------------------------

const withLadder = counter({
  tenure_periods_enabled: true,
  tenure_period_transition: 'beginning_of_cycle',
  tenure_periods: [
    { period_type: 'years', period_length: 1, adjustment_in_cents: 200 },
    { period_type: 'years', period_length: 5, adjustment_in_cents: 400 }
  ]
});

check('the highest rung reached wins, it does not add up', () => {
  const row = oneCycle({ counter: withLadder, employee: employee({ tenure_date: '2019-06-01' }) });
  eq(row.facts.tenure_adjustment_units, 4);
  eq(row.today.value, 26);
});

check('an unreached ladder pays nothing extra', () => {
  const row = oneCycle({ counter: withLadder, employee: employee({ tenure_date: '2026-06-01' }) });
  eq(row.facts.tenure_adjustment_units, 0);
});

check('paying from the milestone prorates the bonus', () => {
  const row = oneCycle({
    counter: { ...withLadder, tenure_period_transition: 'after_milestone' },
    employee: employee({ tenure_date: '2025-07-01' })
  });
  // The first rung lands on 2026-07-01: 184 of 365 days remain.
  eq(Math.round(row.facts.tenure_fraction * 1000) / 1000, 0.504);
});

// --- an authored rule beside it --------------------------------------------------

const partTime =
  'round.nearest(double(allowance.holiday_allowance_in_cents) / 100.0 ' +
  '* (double(contract.working_time_percentage_in_cents) / 10000.0), 0.5)';

check('the part-time rule halves what production pays', () => {
  const row = oneCycle({
    counter: counter(),
    employee: employee({ working_time_percentage_in_cents: 5000 }),
    expression: partTime
  });
  eq(row.today.value, 22);
  eq(row.authored.value, 11);
});

check('the same rule breaks for the full-time population', () => {
  const row = oneCycle({
    counter: counter(),
    employee: employee({ working_time_percentage_in_cents: null }),
    expression: partTime
  });
  eq(row.today.value, 22);
  eq(row.authored.value, undefined);
  eq(row.authored.error.includes('null'), true);
});

check('without the contract bound, the same rule cannot even be read', () => {
  const row = oneCycle({
    counter: counter(),
    employee: employee({ working_time_percentage_in_cents: 5000 }),
    expression: partTime,
    bindContract: false
  });
  eq(row.authored.error.includes('no hay ningún fact llamado contract'), true);
});

check('the tenure rung is bound only when its pull request is on', () => {
  const on = oneCycle({ counter: withLadder, employee: employee(), expression: 'double(tenure.period_length)' });
  eq(on.authored.value, 5);
  const off = oneCycle({
    counter: withLadder,
    employee: employee(),
    expression: 'double(tenure.period_length)',
    bindTenure: false
  });
  eq(off.authored.error.includes('no hay ningún fact llamado tenure'), true);
});

// --- several cycles ---------------------------------------------------------------

check('a five-year window shows the ladder stepping up', () => {
  const rows = simulate({
    counter: withLadder,
    employee: employee({ tenure_date: '2023-06-01', contract_starts_on: '2023-06-01' }),
    from: '2023-01-01',
    to: '2027-12-31'
  });
  eq(rows.length, 5);
  eq(rows.map((r) => r.today.value).join(','), '22,24,24,24,24');
});

check('an employee_hired_date cycle turns on their own anniversary', () => {
  const cycles = cyclesFor(
    counter({ timeoff_cycle: 'employee_hired_date' }),
    employee({ contract_starts_on: '2024-03-15' }),
    { from: new Date('2026-01-01T00:00:00Z'), to: new Date('2026-12-31T00:00:00Z') }
  );
  // The cycle covering 1 January is the one that opened the previous March, so
  // a calendar year of this counter straddles two of them.
  eq(cycles[0].regular_start.toISOString().slice(0, 10), '2025-03-15');
  eq(cycles[0].regular_end.toISOString().slice(0, 10), '2026-03-14');
  eq(cycles[1].regular_start.toISOString().slice(0, 10), '2026-03-15');
});

// --- report -------------------------------------------------------------------------

if (failures.length === 0) {
  console.log(`${passed} comprobaciones, todas en verde`);
} else {
  console.log(`${passed} en verde, ${failures.length} rotas:\n`);
  for (const failure of failures) console.log(`  ✗ ${failure.name}\n    ${failure.message}`);
  process.exitCode = 1;
}
