// The slice of CEL a Factor accrual program can hold, evaluated in the browser.
//
// It exists so the number the simulator shows comes out of the very expression
// on screen, rather than out of a second representation that could disagree
// with it. Fidelity to the backend matters more than coverage here: where
// Factor's CEL refuses something, this refuses it too, with the same reason —
// `max()` does not exist, there is no clock, `duration()` tops out at hours —
// because those refusals are half of what the simulator is reporting.
//
// Namespaces mirror the Ruby extensions: `round` (round.rb), `calendar`
// (calendar.rb), and cel-ruby's own `math`. Values are numbers, strings,
// booleans, null, timestamps (UTC Date) and durations (milliseconds).

const KEYWORDS = new Set(['true', 'false', 'null']);

class CelError extends Error {
  constructor(message, hint) {
    super(message);
    this.name = 'CelError';
    this.hint = hint || null;
  }
}

// --- lexer -------------------------------------------------------------------

function tokenize(source) {
  const tokens = [];
  let i = 0;

  const punctuation = ['&&', '||', '==', '!=', '<=', '>=', '?', ':', '(', ')', ',', '.', '+', '-', '*', '/', '%', '<', '>', '!'];

  while (i < source.length) {
    const char = source[i];

    if (/\s/.test(char)) { i += 1; continue; }

    if (/[0-9]/.test(char) || (char === '.' && /[0-9]/.test(source[i + 1] || ''))) {
      let j = i;
      while (j < source.length && /[0-9._eE]/.test(source[j])) {
        // A dot only continues the number when a digit follows: `1.getDate()` is
        // not a decimal, and neither is the dot in `2.0.foo`.
        if (source[j] === '.' && !/[0-9]/.test(source[j + 1] || '')) break;
        j += 1;
      }
      const text = source.slice(i, j).replace(/_/g, '');
      tokens.push({ type: 'number', value: parseFloat(text), text });
      i = j;
      continue;
    }

    if (char === '"' || char === "'") {
      let j = i + 1;
      let value = '';
      while (j < source.length && source[j] !== char) {
        if (source[j] === '\\') { value += source[j + 1]; j += 2; continue; }
        value += source[j];
        j += 1;
      }
      if (j >= source.length) throw new CelError(`unterminated string starting at position ${i}`);
      tokens.push({ type: 'string', value });
      i = j + 1;
      continue;
    }

    if (/[A-Za-z_]/.test(char)) {
      let j = i;
      while (j < source.length && /[A-Za-z0-9_]/.test(source[j])) j += 1;
      const text = source.slice(i, j);
      tokens.push({ type: KEYWORDS.has(text) ? 'keyword' : 'ident', value: text });
      i = j;
      continue;
    }

    const two = source.slice(i, i + 2);
    const punct = punctuation.includes(two) ? two : punctuation.find((p) => p === char);
    if (!punct) throw new CelError(`unexpected character ${JSON.stringify(char)} at position ${i}`);
    tokens.push({ type: 'punct', value: punct });
    i += punct.length;
  }

  tokens.push({ type: 'eof', value: null });
  return tokens;
}

// --- parser ------------------------------------------------------------------

function parse(source) {
  const tokens = tokenize(source);
  let pos = 0;

  const peek = () => tokens[pos];
  const at = (value) => peek().type === 'punct' && peek().value === value;
  const eat = (value) => { if (at(value)) { pos += 1; return true; } return false; };
  const expect = (value) => {
    if (!eat(value)) throw new CelError(`expected ${JSON.stringify(value)} but found ${JSON.stringify(peek().value)}`);
  };

  function ternary() {
    const condition = logicalOr();
    if (!eat('?')) return condition;
    const whenTrue = ternary();
    expect(':');
    const whenFalse = ternary();
    return { kind: 'ternary', condition, whenTrue, whenFalse };
  }

  function binary(next, operators) {
    let left = next();
    for (;;) {
      const operator = operators.find((op) => at(op));
      if (!operator) return left;
      pos += 1;
      left = { kind: 'binary', operator, left, right: next() };
    }
  }

  const logicalOr = () => binary(logicalAnd, ['||']);
  const logicalAnd = () => binary(equality, ['&&']);
  const equality = () => binary(relational, ['==', '!=']);
  const relational = () => binary(additive, ['<=', '>=', '<', '>']);
  const additive = () => binary(multiplicative, ['+', '-']);
  const multiplicative = () => binary(unary, ['*', '/', '%']);

  function unary() {
    if (eat('!')) return { kind: 'unary', operator: '!', operand: unary() };
    if (eat('-')) return { kind: 'unary', operator: '-', operand: unary() };
    return postfix();
  }

  function args() {
    const list = [];
    if (at(')')) { pos += 1; return list; }
    for (;;) {
      list.push(ternary());
      if (eat(',')) continue;
      expect(')');
      return list;
    }
  }

  function postfix() {
    let node = primary();
    for (;;) {
      if (eat('.')) {
        const name = peek();
        if (name.type !== 'ident') throw new CelError(`expected a name after the dot, found ${JSON.stringify(name.value)}`);
        pos += 1;
        if (eat('(')) node = { kind: 'method', target: node, name: name.value, args: args() };
        else node = { kind: 'member', target: node, name: name.value };
        continue;
      }
      if (eat('(')) { node = { kind: 'call', callee: node, args: args() }; continue; }
      return node;
    }
  }

  function primary() {
    const token = peek();
    if (token.type === 'number') { pos += 1; return { kind: 'number', value: token.value, text: token.text }; }
    if (token.type === 'string') { pos += 1; return { kind: 'string', value: token.value }; }
    if (token.type === 'keyword') {
      pos += 1;
      if (token.value === 'null') return { kind: 'null' };
      return { kind: 'boolean', value: token.value === 'true' };
    }
    if (token.type === 'ident') { pos += 1; return { kind: 'ident', name: token.value }; }
    if (eat('(')) { const inner = ternary(); expect(')'); return inner; }
    throw new CelError(`unexpected expression at ${JSON.stringify(token.value)}`);
  }

  const ast = ternary();
  if (peek().type !== 'eof') throw new CelError(`trailing text from ${JSON.stringify(peek().value)}`);
  return ast;
}

// --- values ------------------------------------------------------------------

const NAMESPACES = new Set(['round', 'calendar', 'math', 'strings']);

class Duration {
  constructor(milliseconds) { this.milliseconds = milliseconds; }
}

function isTimestamp(value) { return value instanceof Date; }

// BigDecimal's ROUND_HALF_UP rounds a tie away from zero; JS Math.round breaks
// ties toward +Infinity, so -2.5 would differ. The quotient is also snapped to
// ten decimals first: the backend divides in BigDecimal, where 0.1/0.01 is
// exactly 10, and binary floating point makes it 10.000000000000002 here.
function halfUp(value) {
  const snapped = parseFloat(value.toPrecision(12));
  return Math.sign(snapped) * Math.round(Math.abs(snapped));
}

function requireNumber(value, where) {
  if (value === null || value === undefined) {
    throw new CelError(
      `${where}: the numeric argument evaluated to null`,
      'A nullable field binds to null and Factor has no optional inputs, so the expression breaks for every employee whose field is empty.'
    );
  }
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new CelError(`${where}: expected a number and got ${describe(value)}`);
  }
  return value;
}

function describe(value) {
  if (value === null || value === undefined) return 'null';
  if (isTimestamp(value)) return `timestamp ${value.toISOString().slice(0, 10)}`;
  if (value instanceof Duration) return 'duration';
  if (typeof value === 'object') return 'entity';
  return `${typeof value} ${JSON.stringify(value)}`;
}

// --- extensions --------------------------------------------------------------

function roundNamespace(name, argv) {
  const stepArg = (value) => {
    const step = requireNumber(value, `round.${name}`);
    if (step === 0) throw new CelError(`round.${name}: the step cannot be zero`);
    return step;
  };

  if (name === 'nearest' || name === 'up' || name === 'down' || name === 'away_from_zero') {
    if (argv.length !== 2) throw new CelError(`round.${name} takes 2 arguments and got ${argv.length}`);
    const num = requireNumber(argv[0], `round.${name}`);
    const step = stepArg(argv[1]);

    if (name === 'nearest') return halfUp(num / step) * step;
    if (name === 'up') return Math.ceil(parseFloat((num / step).toPrecision(12))) * step;
    if (name === 'down') return Math.floor(parseFloat((num / step).toPrecision(12))) * step;
    const magnitude = Math.ceil(parseFloat((Math.abs(num) / Math.abs(step)).toPrecision(12))) * Math.abs(step);
    return num < 0 ? -magnitude : magnitude;
  }

  if (name === 'banded') {
    if (argv.length !== 4) throw new CelError(`round.banded takes 4 arguments and got ${argv.length}`);
    const num = requireNumber(argv[0], 'round.banded');
    const step = stepArg(argv[1]);
    const lower = requireNumber(argv[2], 'round.banded');
    const upper = requireNumber(argv[3], 'round.banded');
    const magnitude = Math.abs(num);
    const whole = Math.floor(magnitude);
    const fraction = magnitude - whole;
    let result;
    if (fraction < lower) result = whole;
    else if (fraction > upper) result = Math.ceil(magnitude);
    else result = whole + halfUp(fraction / step) * step;
    return num < 0 ? -result : result;
  }

  throw new CelError(`round.${name} does not exist`, 'The round functions are nearest, up, down, away_from_zero and banded.');
}

function mathNamespace(name, argv) {
  if (name !== 'greatest' && name !== 'least') {
    throw new CelError(`math.${name} does not exist`, 'The math namespace has only greatest and least.');
  }
  const numbers = argv.map((value, index) => requireNumber(value, `math.${name} (argumento ${index + 1})`));
  if (numbers.length === 0) throw new CelError(`math.${name} needs at least one argument`);
  return name === 'greatest' ? Math.max(...numbers) : Math.min(...numbers);
}

function calendarNamespace(name, argv, context) {
  const asTimestamp = (value, where) => {
    if (!isTimestamp(value)) throw new CelError(`${where}: expected a timestamp and got ${describe(value)}`);
    return value;
  };

  if (name === 'months_between') {
    const from = asTimestamp(argv[0], 'calendar.months_between');
    const to = asTimestamp(argv[1], 'calendar.months_between');
    // Month boundaries crossed, day of month ignored, and deliberately exclusive.
    return (to.getUTCFullYear() - from.getUTCFullYear()) * 12 + (to.getUTCMonth() - from.getUTCMonth());
  }

  if (name === 'period_start' || name === 'period_end') {
    const at = asTimestamp(argv[0], `calendar.${name}`);
    const unit = argv[1];
    const units = ['daily', 'weekly', 'monthly', 'quarterly', 'yearly'];
    if (!units.includes(unit)) {
      throw new CelError(`calendar.${name}: unknown unit ${JSON.stringify(unit)}`, `The units are ${units.join(', ')}.`);
    }
    // The browser has no tz database beyond the host's, and the simulated
    // employee is modelled in UTC, so truncation happens in UTC here. Stated
    // rather than hidden: a rule whose result turns on the zone is out of the
    // simulator's reach.
    const y = at.getUTCFullYear();
    const m = at.getUTCMonth();
    const d = at.getUTCDate();
    const start = {
      daily: () => Date.UTC(y, m, d),
      weekly: () => { const dow = (at.getUTCDay() + 6) % 7; return Date.UTC(y, m, d - dow); },
      monthly: () => Date.UTC(y, m, 1),
      quarterly: () => Date.UTC(y, Math.floor(m / 3) * 3, 1),
      yearly: () => Date.UTC(y, 0, 1)
    }[unit]();
    if (name === 'period_start') return new Date(start);
    const next = {
      daily: () => Date.UTC(y, m, d + 1),
      weekly: () => { const dow = (at.getUTCDay() + 6) % 7; return Date.UTC(y, m, d - dow + 7); },
      monthly: () => Date.UTC(y, m + 1, 1),
      quarterly: () => Date.UTC(y, Math.floor(m / 3) * 3 + 3, 1),
      yearly: () => Date.UTC(y + 1, 0, 1)
    }[unit]();
    return new Date(next - 86400000);
  }

  if (name === 'count_working_days') {
    const from = asTimestamp(argv[0], 'calendar.count_working_days');
    const to = asTimestamp(argv[1], 'calendar.count_working_days');
    // Monday to Friday minus company holidays, inclusive of both ends. The
    // holiday list is whatever the simulated company declares; the backend reads
    // the tenant's own, deduplicated across locations.
    const holidays = new Set((context.holidays || []).map((day) => day.slice(0, 10)));
    let count = 0;
    for (let day = new Date(from.getTime()); day <= to; day.setUTCDate(day.getUTCDate() + 1)) {
      const weekday = day.getUTCDay();
      if (weekday === 0 || weekday === 6) continue;
      if (holidays.has(day.toISOString().slice(0, 10))) continue;
      count += 1;
    }
    return count;
  }

  if (name === 'country_timezone') {
    throw new CelError(
      'calendar.country_timezone is not implemented in the simulator',
      'It exists in the backend; here it changes no result because the simulated employee lives in UTC.'
    );
  }

  throw new CelError(`calendar.${name} does not exist`, 'The calendar namespace has period_start, period_end, count_working_days, months_between and country_timezone.');
}

// Refusals the backend makes, reproduced so the simulator reports the real
// reason instead of inventing a number.
const REFUSED_GLOBALS = {
  max: 'max() does not exist in CEL: it is math.greatest.',
  min: 'min() does not exist in CEL: it is math.least.',
  sum: 'cel-ruby has no fold: sum, reduce and bare min/max all raise.',
  reduce: 'cel-ruby has no fold: sum, reduce and bare min/max all raise.',
  today: "Factor's CEL has no clock: there is no today() and no now(). Dates arrive as bound facts.",
  now: "Factor's CEL has no clock: there is no today() and no now(). Dates arrive as bound facts.",
  duration: 'duration() no pasa de horas: duration("160d") y duration("1w") revientan. Usa (a - b).getHours() / 24.'
};

// --- evaluation --------------------------------------------------------------

function evaluate(source, bindings, options = {}) {
  const ast = typeof source === 'string' ? parse(source) : source;
  const context = { holidays: options.holidays || [] };
  const reads = new Set();

  function lookup(name) {
    if (NAMESPACES.has(name)) return { namespace: name };
    if (Object.prototype.hasOwnProperty.call(bindings, name)) {
      reads.add(name);
      return bindings[name];
    }
    throw new CelError(
      `there is no fact called ${name}`,
      'Only what the evaluator binds can be read: any other reference evaluates to a missing binding and Factor rejects it at save time.'
    );
  }

  function walk(node) {
    switch (node.kind) {
      case 'number': return node.value;
      case 'string': return node.value;
      case 'boolean': return node.value;
      case 'null': return null;
      case 'ident': return lookup(node.name);

      case 'unary': {
        const operand = walk(node.operand);
        if (node.operator === '!') return !operand;
        return -requireNumber(operand, 'negation');
      }

      case 'ternary':
        return walk(node.condition) ? walk(node.whenTrue) : walk(node.whenFalse);

      case 'binary': {
        const { operator } = node;
        if (operator === '&&') return walk(node.left) && walk(node.right);
        if (operator === '||') return walk(node.left) || walk(node.right);

        const left = walk(node.left);
        const right = walk(node.right);

        if (operator === '==' || operator === '!=') {
          const equal = isTimestamp(left) && isTimestamp(right) ? left.getTime() === right.getTime() : left === right;
          return operator === '==' ? equal : !equal;
        }

        if (isTimestamp(left) && isTimestamp(right)) {
          if (operator === '-') return new Duration(left.getTime() - right.getTime());
          const comparison = left.getTime() - right.getTime();
          if (operator === '<') return comparison < 0;
          if (operator === '<=') return comparison <= 0;
          if (operator === '>') return comparison > 0;
          if (operator === '>=') return comparison >= 0;
        }

        if (operator === '+' && typeof left === 'string' && typeof right === 'string') return left + right;

        const a = requireNumber(left, `operator ${operator}`);
        const b = requireNumber(right, `operator ${operator}`);
        switch (operator) {
          case '+': return a + b;
          case '-': return a - b;
          case '*': return a * b;
          case '/':
            if (b === 0) throw new CelError('division by zero');
            return a / b;
          case '%':
            if (b === 0) throw new CelError('modulo by zero');
            return a % b;
          case '<': return a < b;
          case '<=': return a <= b;
          case '>': return a > b;
          case '>=': return a >= b;
          default: throw new CelError(`operator ${operator} no soportado`);
        }
      }

      case 'member': {
        const target = walk(node.target);
        if (target && target.namespace) {
          throw new CelError(`${target.namespace}.${node.name} is used as a value but is a function`);
        }
        if (target === null || target === undefined) {
          throw new CelError(`no puedo leer ${node.name} de un valor nulo`);
        }
        if (typeof target !== 'object' || isTimestamp(target)) {
          throw new CelError(`${describe(target)} has no fields, and is asked for ${node.name}`);
        }
        if (!Object.prototype.hasOwnProperty.call(target, node.name)) {
          const entity = target.__entity ? ` of ${target.__entity}` : '';
          throw new CelError(
            `the field ${node.name}${entity} is not on the allowlist`,
            'Factor rejects at save time any reference not registered for that entity.'
          );
        }
        const path = node.target.kind === 'ident' ? `${node.target.name}.${node.name}` : node.name;
        reads.add(path);
        const value = target[node.name];
        return value === undefined ? null : value;
      }

      case 'method': {
        const target = walk(node.target);
        const argv = node.args.map(walk);

        if (target && target.namespace) {
          if (target.namespace === 'round') return roundNamespace(node.name, argv);
          if (target.namespace === 'math') return mathNamespace(node.name, argv);
          if (target.namespace === 'calendar') return calendarNamespace(node.name, argv, context);
          throw new CelError(`the ${target.namespace} namespace is not implemented in the simulator`);
        }

        if (isTimestamp(target)) {
          switch (node.name) {
            case 'getDate': return target.getUTCDate();
            case 'getMonth': return target.getUTCMonth(); // 0-based, como cel-ruby
            case 'getFullYear': return target.getUTCFullYear();
            case 'getDayOfWeek': return target.getUTCDay(); // 0 = domingo
            case 'getHours': return target.getUTCHours();
            default: throw new CelError(`a timestamp does not respond to ${node.name}()`);
          }
        }

        if (target instanceof Duration) {
          if (node.name === 'getHours') return Math.trunc(target.milliseconds / 3600000);
          if (node.name === 'getMinutes') return Math.trunc(target.milliseconds / 60000);
          if (node.name === 'getSeconds') return Math.trunc(target.milliseconds / 1000);
          throw new CelError(`a duration does not respond to ${node.name}()`);
        }

        throw new CelError(`${describe(target)} does not respond to ${node.name}()`);
      }

      case 'call': {
        if (node.callee.kind !== 'ident') throw new CelError('only named functions can be called');
        const name = node.callee.name;
        if (REFUSED_GLOBALS[name]) throw new CelError(`${name}() does not exist in Factor's CEL`, REFUSED_GLOBALS[name]);
        const argv = node.args.map(walk);
        if (name === 'double') return requireNumber(argv[0], 'double()');
        if (name === 'int') return Math.trunc(requireNumber(argv[0], 'int()'));
        if (name === 'string') return String(argv[0]);
        throw new CelError(`the function ${name}() does not exist`);
      }

      default:
        throw new CelError(`nodo ${node.kind} no soportado`);
    }
  }

  const value = walk(ast);
  return { value, reads: [...reads].sort() };
}

// Which facts an expression reads, without running it — so the simulator can say
// what a rule needs before deciding whether those facts are reachable.
function referencedFacts(source) {
  const ast = typeof source === 'string' ? parse(source) : source;
  const found = new Set();

  // A member chain is one fact, however deep: `contract.employee.default_location
  // .country` is the country, not four separate reads. Returns the dotted path
  // when the chain is rooted in an identifier, and null when it is not (a method
  // call in the middle, say), so the caller can fall back to walking children.
  function chainPath(node) {
    if (node.kind === 'ident') return NAMESPACES.has(node.name) ? null : node.name;
    if (node.kind !== 'member') return null;
    const parent = chainPath(node.target);
    return parent === null ? null : `${parent}.${node.name}`;
  }

  function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (node.kind === 'ident' && !NAMESPACES.has(node.name)) found.add(node.name);
    if (node.kind === 'member') {
      const path = chainPath(node);
      if (path !== null) {
        found.add(path);
        // The prefixes of a path are not reads of their own.
        const parts = path.split('.');
        for (let i = 1; i < parts.length; i += 1) found.delete(parts.slice(0, i).join('.'));
        return;
      }
    }
    // `double(x)` names a function, not a fact, so the callee never counts.
    if (node.kind === 'call') {
      node.args.forEach(walk);
      return;
    }
    for (const key of Object.keys(node)) {
      const child = node[key];
      if (Array.isArray(child)) child.forEach(walk);
      else walk(child);
    }
  }

  walk(ast);
  return [...found].sort();
}

export { parse, evaluate, referencedFacts, CelError, Duration };
