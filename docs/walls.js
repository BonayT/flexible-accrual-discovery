// The four walls a rule meets, and which one stops it first.
//
// The simulator's whole answer is this ordering. A rule that cannot reach its
// data never gets to be an expression; an expression CEL refuses never reaches
// a counter; a counter the gate rejects never runs; and a number that runs can
// still fail to govern what the employee is allowed to book. Reporting only the
// first wall would hide the others, so each one is assessed and the verdict
// names the earliest that bites.

const BINDING_LABELS = {
  today: 'llega hoy',
  pr_112683: 'llega con #112683',
  pr_112685: 'llega con #112685'
};

// Where a root name comes from, per binding state: an entity identifier, or the
// marker `scalar` for the floats and dates the evaluator feeds directly.
function rootIndex(catalog, enabled) {
  const roots = {};
  for (const [state, binding] of Object.entries(catalog.bindings)) {
    if (state !== 'today' && !enabled.includes(state)) continue;
    for (const [name, identifier] of Object.entries(binding.entities || {})) {
      roots[name] = { kind: 'entity', identifier, state, caveat: binding.caveat };
    }
    for (const name of binding.scalars || []) {
      roots[name] = { kind: 'scalar', state };
    }
  }
  return roots;
}

// Every root the catalog could offer if every pending binding were on, so a
// missing one can be told apart from a misspelt one.
function allRoots(catalog) {
  return rootIndex(catalog, Object.keys(catalog.bindings));
}

// Walks a dotted path through the entity graph the way the CEL environment
// expands it, and says where it lands.
function resolvePath(catalog, roots, path) {
  const [rootName, ...rest] = path.split('.');
  const root = roots[rootName];
  if (!root) return { reachable: false, reason: 'root_missing', rootName };

  if (root.kind === 'scalar') {
    if (rest.length > 0) return { reachable: false, reason: 'scalar_has_no_fields', rootName };
    return { reachable: true, kind: 'scalar', state: root.state, path };
  }

  let identifier = root.identifier;
  let throughCollection = false;
  const hops = [];

  for (let i = 0; i < rest.length; i += 1) {
    const name = rest[i];
    const entity = catalog.entities[identifier];
    if (!entity) return { reachable: false, reason: 'entity_unregistered', identifier };

    const last = i === rest.length - 1;
    const field = entity.fields[name];
    if (last && field) {
      return {
        reachable: true,
        kind: 'field',
        state: root.state,
        caveat: root.caveat,
        identifier,
        field: name,
        descriptor: field,
        source: entity.source,
        throughCollection,
        hops
      };
    }

    const association = entity.associations[name];
    if (!association || !association.target) {
      return { reachable: false, reason: 'field_not_allowlisted', identifier, field: name, source: entity.source };
    }

    if (['has_many', 'has_many_through'].includes(association.kind)) throughCollection = true;
    hops.push({ name, from: identifier, to: association.target, collection: throughCollection });
    identifier = association.target;
  }

  return { reachable: false, reason: 'path_ends_on_an_entity', identifier };
}

// --- wall 1: the data ----------------------------------------------------------

function assessData(catalog, reads, enabled) {
  const roots = rootIndex(catalog, enabled);
  const everything = allRoots(catalog);

  const found = reads.map((path) => {
    const resolved = resolvePath(catalog, roots, path);
    if (resolved.reachable) return { path, ...resolved };

    // Not reachable with what is switched on. Is it reachable at all?
    const ifEverything = resolvePath(catalog, everything, path);
    return { path, ...resolved, availableIn: ifEverything.reachable ? ifEverything.state : null };
  });

  const blocked = found.filter((f) => !f.reachable);
  const trapped = found.filter((f) => f.reachable && f.throughCollection);

  return {
    wall: 'dato',
    passes: blocked.length === 0 && trapped.length === 0,
    facts: found,
    blocked,
    trapped
  };
}

// --- wall 2: the operation ------------------------------------------------------

function assessOperation(result) {
  if (!result) return { wall: 'operación', passes: false, reason: 'sin expresión' };
  if (result.error) return { wall: 'operación', passes: false, reason: result.error, hint: result.hint };
  return { wall: 'operación', passes: true };
}

// --- wall 3: the counter ---------------------------------------------------------

// CounterProgramAssignment.eligible?, reproduced. Exposure does not touch this:
// a counter that fails it is never assigned a program, so the rule is inert no
// matter how good it is.
function assessCounter(counter, catalog) {
  const failures = [];
  if (counter.use_availability && counter.use_availability !== 'all_days') {
    failures.push(`la cadencia es ${counter.use_availability} y el gate exige all_days`);
  }
  if (counter.source_units && counter.source_units !== 'base_units') {
    failures.push(`el contador es ${counter.source_units} y el gate exige base_units`);
  }
  if (counter.feature_enabled === false) {
    failures.push('la compañía no tiene DEV_FLEXIBLE_ACCRUAL_AUTHORITATIVE encendida');
  }
  return {
    wall: 'elegibilidad',
    passes: failures.length === 0,
    failures,
    source: catalog.eligibility_gate.source
  };
}

// --- wall 4: where the number lands ------------------------------------------------

// A rule that computes a different number from legacy shows that number, and the
// booking gate and the carry-over keep using legacy's. Not a refusal: a warning
// that only fires when the two disagree, because that is when it bites.
function assessLanding(catalog, todayValue, authoredValue) {
  const diverges =
    typeof todayValue === 'number' && typeof authoredValue === 'number' &&
    Math.abs(todayValue - authoredValue) > 1e-9;

  return {
    wall: 'aterrizaje',
    passes: !diverges,
    diverges,
    gaps: catalog.landing_gaps
  };
}

// --- the verdict -------------------------------------------------------------------

const ORDER = ['dato', 'operación', 'elegibilidad', 'aterrizaje'];

function assess({ catalog, counter, reads, result, todayValue, enabled = ['pr_112683', 'pr_112685'] }) {
  const walls = [
    assessData(catalog, reads, enabled),
    assessOperation(result),
    assessCounter(counter, catalog),
    assessLanding(catalog, todayValue, result && result.value)
  ];

  const stoppedBy = ORDER.map((name) => walls.find((w) => w.wall === name)).find((w) => !w.passes);

  return {
    walls,
    stoppedBy: stoppedBy ? stoppedBy.wall : null,
    // "Se cubre" means the number is computed AND governs. A divergence at the
    // landing wall is not a refusal, so it reads as covered-with-a-warning.
    covered: !stoppedBy || stoppedBy.wall === 'aterrizaje',
    warning: stoppedBy && stoppedBy.wall === 'aterrizaje'
  };
}

export { assess, resolvePath, rootIndex, allRoots, BINDING_LABELS };
