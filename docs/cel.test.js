// Pins the interpreter against the backend's own semantics, since the whole
// point of writing one was that the number on screen comes out of the
// expression on screen. Where a case mirrors a documented example from
// `factor/cel/extensions/round.rb` or `calendar.rb`, the comment says so.
//
//   node docs/cel.test.js

import { evaluate, parse, referencedFacts, CelError } from './cel.js';

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
  const same = Number.isFinite(expected) && Number.isFinite(actual)
    ? Math.abs(actual - expected) < 1e-9
    : actual === expected;
  if (!same) throw new Error(`${note || ''} esperaba ${JSON.stringify(expected)}, obtuve ${JSON.stringify(actual)}`);
}

function run(source, bindings = {}, options = {}) {
  return evaluate(source, bindings, options).value;
}

function refuses(source, bindings, fragment) {
  try {
    evaluate(source, bindings || {});
  } catch (error) {
    if (!(error instanceof CelError)) throw new Error(`esperaba CelError, obtuve ${error.name}: ${error.message}`);
    const haystack = `${error.message} ${error.hint || ''}`;
    if (!haystack.includes(fragment)) {
      throw new Error(`el mensaje no menciona ${JSON.stringify(fragment)}: ${haystack}`);
    }
    return;
  }
  throw new Error('esperaba que fallase y no falló');
}

const utc = (iso) => new Date(`${iso}T00:00:00Z`);

// --- arithmetic, precedence, ternaries -------------------------------------

check('arithmetic honours precedence', () => eq(run('2.0 + 3.0 * 4.0'), 14));
check('parentheses override it', () => eq(run('(2.0 + 3.0) * 4.0'), 20));
check('ternary picks a branch', () => eq(run('1.0 < 2.0 ? 10.0 : 20.0'), 10));
check('ternaries nest', () => eq(run('false ? 1.0 : (true ? 2.0 : 3.0)'), 2));
check('unary minus', () => eq(run('-3.0 + 1.0'), -2));
check('logical and short-circuits', () => eq(run('false && (1.0 / 0.0) > 0.0'), false));
check('string equality', () => eq(run("'a' == 'a'"), true));
check('double() coerces', () => eq(run('double(3.0) / 2.0'), 1.5));

// --- entity fields ---------------------------------------------------------

const allowance = { __entity: 'timeoff.allowance', holiday_allowance_in_cents: 2200, proration_type: 'proration_enabled' };
const contract = { __entity: 'contracts.contract_version', working_time_percentage_in_cents: 5000, ends_on: null };

check('reads a field off a bound entity', () =>
  eq(run('double(allowance.holiday_allowance_in_cents) / 100.0', { allowance }), 22));

check('the part-time rule pays half', () =>
  eq(
    run(
      'double(allowance.holiday_allowance_in_cents) / 100.0 * (double(contract.working_time_percentage_in_cents) / 10000.0)',
      { allowance, contract }
    ),
    11
  ));

check('an unbound root is refused, not silently null', () =>
  refuses('employee.terminated_on > cycle_start_date', { allowance }, 'no hay ningún fact llamado employee'));

check('a field outside the allowlist is refused', () =>
  refuses('allowance.maximum_amount_in_cents > 0.0', { allowance }, 'no está en el allowlist'));

// The nullable %FTE case: NULL means full time, and Factor has no optional
// inputs, so the rule that works for the part-timer breaks for everyone else.
check('a null numeric argument is reported, not treated as zero', () =>
  refuses(
    'round.nearest(double(contract.working_time_percentage_in_cents) / 100.0, 0.5)',
    { contract: { __entity: 'contracts.contract_version', working_time_percentage_in_cents: null } },
    'null'
  ));

// --- round.* ---------------------------------------------------------------
// The four examples in the extension's own docstring.

check('round.nearest to a quarter', () => eq(run('round.nearest(17.267, 0.25)'), 17.25));
check('round.nearest to a half', () => eq(run('round.nearest(17.267, 0.5)'), 17.5));
check('round.nearest to two decimals', () => eq(run('round.nearest(17.267, 0.01)'), 17.27));
check('round.up ceils to the whole day', () => eq(run('round.up(17.001, 1.0)'), 18));
check('round.down floors to the whole day', () => eq(run('round.down(17.999, 1.0)'), 17));

// ROUND_HALF_UP in BigDecimal is half away from zero, which JS Math.round is not.
check('a tie rounds away from zero, upwards', () => eq(run('round.nearest(0.5, 1.0)'), 1));
check('a tie rounds away from zero, downwards', () => eq(run('round.nearest(-0.5, 1.0)'), -1));
check('round.away_from_zero on a negative', () => eq(run('round.away_from_zero(-17.1, 0.5)'), -17.5));
check('round.up on a negative ceils toward zero', () => eq(run('round.up(-17.1, 0.5)'), -17));

// Binary floating point would give 10.000000000000002 for 0.1 / 0.01, where the
// backend divides in BigDecimal and gets exactly 10.
check('no floating point crumbs', () => eq(run('round.nearest(0.1, 0.01)'), 0.1));
check('a whole value on the step is left alone', () => eq(run('round.up(17.5, 0.5)'), 17.5));

check('a zero step is refused', () => refuses('round.nearest(1.0, 0.0)', {}, 'cero'));

// The half-day band: below .25 floors, .25 to .5 lands on the half, above ceils.
check('round.banded floors under the lower bound', () => eq(run('round.banded(10.2, 0.5, 0.25, 0.5)'), 10));
check('round.banded lands on the half inside the band', () => eq(run('round.banded(10.3, 0.5, 0.25, 0.5)'), 10.5));
check('round.banded ceils above the upper bound', () => eq(run('round.banded(10.6, 0.5, 0.25, 0.5)'), 11));

// --- math ------------------------------------------------------------------

check('math.greatest is the floor at zero', () => eq(run('math.greatest(-3.0, 0.0)'), 0));
check('math.least caps', () => eq(run('math.least(42.0, 30.0)'), 30));
check('the clamp the guide teaches', () => eq(run('math.least(math.greatest(round.nearest(31.4, 1.0), 0.0), 30.0)'), 30));

// --- timestamps ------------------------------------------------------------

const dates = {
  hire_date: utc('2026-03-15'),
  cycle_start_date: utc('2026-01-01'),
  cycle_end_date: utc('2026-12-31'),
  tenure_date: utc('2019-06-01')
};

check('getDate is the day of month', () => eq(run('hire_date.getDate()', dates), 15));
check('getMonth is 0-based', () => eq(run('hire_date.getMonth()', dates), 2));
check('getFullYear', () => eq(run('hire_date.getFullYear()', dates), 2026));
check('getDayOfWeek is 0 for Sunday', () => eq(run('cycle_start_date.getDayOfWeek()', { cycle_start_date: utc('2026-03-15') }), 0));

check('timestamps compare', () => eq(run('hire_date > cycle_start_date', dates), true));

// The tenure threshold the handoff writes as days, since duration() cannot.
check('subtracting timestamps gives hours', () =>
  eq(run('(cycle_end_date - tenure_date).getHours() / 24.0 >= 160.0', dates), true));

// calendar.months_between is exclusive: January to December is 11.
check('months_between is exclusive', () =>
  eq(run('double(calendar.months_between(cycle_start_date, cycle_end_date))', dates), 11));
check('months_between ignores the day of month', () =>
  eq(run('double(calendar.months_between(hire_date, cycle_end_date))', dates), 9));

check('period_start truncates to the month', () =>
  eq(run("calendar.period_start(hire_date, 'monthly', 'Europe/Madrid').getDate()", dates), 1));
check('period_end lands on the last day of the month', () =>
  eq(run("calendar.period_end(hire_date, 'monthly', 'Europe/Madrid').getDate()", dates), 31));
check('an unknown unit is refused', () =>
  refuses("calendar.period_start(hire_date, 'fortnightly', 'Europe/Madrid')", dates, 'desconocida'));

check('count_working_days excludes weekends', () =>
  eq(run('double(calendar.count_working_days(a, b))', { a: utc('2026-03-02'), b: utc('2026-03-08') }), 5));
check('count_working_days excludes company holidays', () =>
  eq(
    run('double(calendar.count_working_days(a, b))', { a: utc('2026-03-02'), b: utc('2026-03-08') }, { holidays: ['2026-03-04'] }),
    4
  ));

// --- what Factor's CEL refuses ---------------------------------------------

check('there is no max()', () => refuses('max(1.0, 2.0)', {}, 'math.greatest'));
check('there is no min()', () => refuses('min(1.0, 2.0)', {}, 'math.least'));
check('there is no clock', () => refuses('today()', {}, 'reloj'));
check('duration() tops out at hours', () => refuses("duration('160d')", {}, 'getHours'));
check('there is no fold', () => refuses('sum(1.0)', {}, 'fold'));

// --- reading an expression without running it ------------------------------

check('referencedFacts names the roots and their paths', () => {
  const found = referencedFacts(
    'hire_date > cycle_start_date ? double(contract.working_time_percentage_in_cents) : double(allowance.holiday_allowance_in_cents)'
  );
  eq(found.join(','), 'allowance.holiday_allowance_in_cents,contract.working_time_percentage_in_cents,cycle_start_date,hire_date');
});

check('referencedFacts ignores the namespaces', () => {
  const found = referencedFacts('round.nearest(math.greatest(active_days, 0.0), 1.0)');
  eq(found.join(','), 'active_days');
});

check('referencedFacts keeps a whole chain as one fact', () => {
  const found = referencedFacts('contract.employee.default_location.country == "ES"');
  eq(found.join(','), 'contract.employee.default_location.country');
});

check('a chain reads through the graph', () =>
  eq(
    run('contract.employee.default_location.country', {
      contract: { __entity: 'x', employee: { __entity: 'y', default_location: { __entity: 'z', country: 'ES' } } }
    }),
    'ES'
  ));

// --- the canonical shape ---------------------------------------------------
// The generated per-counter expression, in miniature: day proration or the flat
// entitlement, plus the tenure term, times the cadence window, all rounded.

check('the canonical shape evaluates end to end', () => {
  const source =
    "round.nearest(((allowance.proration_type == 'proration_enabled' " +
    '? (double(allowance.holiday_allowance_in_cents) / 100.0) * (active_days / cycle_days) ' +
    ': double(allowance.holiday_allowance_in_cents) / 100.0) ' +
    '+ tenure_adjustment_units * tenure_fraction) * availability_fraction, 0.5)';
  const value = run(source, {
    allowance,
    active_days: 183.0,
    cycle_days: 365.0,
    tenure_adjustment_units: 2.0,
    tenure_fraction: 1.0,
    availability_fraction: 1.0
  });
  eq(value, 13); // 22 * 183/365 = 11.03, + 2 = 13.03, nearest half = 13
});

// --- report ----------------------------------------------------------------

if (failures.length === 0) {
  console.log(`${passed} comprobaciones, todas en verde`);
} else {
  console.log(`${passed} en verde, ${failures.length} rotas:\n`);
  for (const failure of failures) console.log(`  ✗ ${failure.name}\n    ${failure.message}`);
  process.exitCode = 1;
}
