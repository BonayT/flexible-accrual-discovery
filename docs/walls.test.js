// The verdict: which wall stops a rule first, and does it name the right one.
//
//   node docs/walls.test.js

import { readFileSync } from 'node:fs';
import { assess, resolvePath, rootIndex } from './walls.js';
import { referencedFacts } from './cel.js';

const catalog = JSON.parse(readFileSync(new URL('./catalog.json', import.meta.url), 'utf8'));

let passed = 0;
const failures = [];
const check = (name, fn) => { try { fn(); passed += 1; } catch (e) { failures.push({ name, message: e.message }); } };
const eq = (a, b, n) => { if (a !== b) throw new Error(`${n || ''} esperaba ${JSON.stringify(b)}, obtuve ${JSON.stringify(a)}`); };

const counter = { use_availability: 'all_days', source_units: 'base_units', feature_enabled: true };
const ok = (value) => ({ value });

const verdict = (expression, opts = {}) =>
  assess({ catalog, counter: opts.counter || counter, reads: referencedFacts(expression), result: opts.result || ok(11), todayValue: opts.todayValue ?? 22, enabled: opts.enabled });

// --- reachability ---------------------------------------------------------------

check('the counter is reachable today', () => {
  const r = resolvePath(catalog, rootIndex(catalog, []), 'allowance.holiday_allowance_in_cents');
  eq(r.reachable, true); eq(r.state, 'today');
});

check('the contract is not, until #112683', () => {
  eq(resolvePath(catalog, rootIndex(catalog, []), 'contract.working_time_percentage_in_cents').reachable, false);
  const withPr = resolvePath(catalog, rootIndex(catalog, ['pr_112683']), 'contract.working_time_percentage_in_cents');
  eq(withPr.reachable, true); eq(withPr.state, 'pr_112683');
});

check('the workplace comes free with the contract, by navigation', () => {
  const r = resolvePath(catalog, rootIndex(catalog, ['pr_112683']), 'contract.employee.default_location.country');
  eq(r.reachable, true);
  eq(r.hops.map((h) => h.to).join(' → '), 'employees.employee → locations.location');
  eq(r.throughCollection, false);
});

check('anything behind a collection is flagged as trapped', () => {
  const r = resolvePath(catalog, rootIndex(catalog, ['pr_112683']), 'contract.employee.leaves.start_on');
  eq(r.reachable, true); eq(r.throughCollection, true);
});

check('a field outside the allowlist says so, and names its resource', () => {
  const r = resolvePath(catalog, rootIndex(catalog, []), 'allowance.maximum_amount_in_cents');
  eq(r.reachable, false); eq(r.reason, 'field_not_allowlisted');
  eq(r.source.includes('allowance'), true);
});

// --- the verdict ------------------------------------------------------------------

check('a rule reading only what is bound today is covered', () => {
  const v = verdict('double(allowance.holiday_allowance_in_cents) / 100.0', { result: ok(22), todayValue: 22 });
  eq(v.stoppedBy, null); eq(v.covered, true);
});

check('the part-time rule is stopped by the data before the PRs', () => {
  const v = verdict('double(contract.working_time_percentage_in_cents)', { enabled: [] });
  eq(v.stoppedBy, 'dato'); eq(v.covered, false);
  eq(v.walls[0].blocked[0].availableIn, 'pr_112683');
});

check('and is covered once the contract is bound', () => {
  const v = verdict('double(contract.working_time_percentage_in_cents)');
  eq(v.stoppedBy, 'aterrizaje'); eq(v.covered, true); eq(v.warning, true);
});

check('a headcount rule is stopped by the data with nothing to enable', () => {
  const v = verdict('double(location.headcount)');
  eq(v.stoppedBy, 'dato');
  eq(v.walls[0].blocked[0].availableIn, null);
});

check('a broken expression is stopped by the operation', () => {
  const v = verdict('double(allowance.holiday_allowance_in_cents)', { result: { error: 'max() no existe' } });
  eq(v.stoppedBy, 'operación');
});

check('a monthly counter is stopped by the gate, however good the rule', () => {
  const v = verdict('double(allowance.holiday_allowance_in_cents) / 100.0', {
    counter: { ...counter, use_availability: 'monthly_first_day' },
    result: ok(22), todayValue: 22
  });
  eq(v.stoppedBy, 'elegibilidad');
  eq(v.walls[2].failures[0].includes('all_days'), true);
});

check('a by_worked_time counter is stopped by the same gate', () => {
  const v = verdict('double(allowance.holiday_allowance_in_cents) / 100.0', {
    counter: { ...counter, source_units: 'by_worked_time' }, result: ok(22), todayValue: 22
  });
  eq(v.stoppedBy, 'elegibilidad');
});

check('a number that differs from legacy warns about where it lands', () => {
  const v = verdict('double(allowance.holiday_allowance_in_cents) / 100.0', { result: ok(11), todayValue: 22 });
  eq(v.stoppedBy, 'aterrizaje'); eq(v.warning, true);
  eq(v.walls[3].gaps.length, 2);
});

check('the data wall is reported before the gate, when both bite', () => {
  const v = verdict('double(contract.working_time_percentage_in_cents)', {
    counter: { ...counter, use_availability: 'daily' }, enabled: []
  });
  eq(v.stoppedBy, 'dato');
});

if (failures.length === 0) console.log(`${passed} comprobaciones, todas en verde`);
else { console.log(`${passed} en verde, ${failures.length} rotas:\n`); for (const f of failures) console.log(`  ✗ ${f.name}\n    ${f.message}`); process.exitCode = 1; }
