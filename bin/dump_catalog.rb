# Dumps the Factor entity catalog the accrual simulator reads, straight from files
# in the monorepo: no Rails, no database, no boot.
#
#   ruby bin/dump_catalog.rb ~/code/factorial > docs/catalog.json
#
# Sources, in the order they are merged:
#   registry_snapshot.yml  fields + Sorbet types + association names + filters
#   <component>/app/resources/**.yml  descriptions, and the relationship targets
#     the snapshot does not carry (it stores association names only)
#
# Descriptions marked `serialization_groups: [private]` are NOT reproduced: the
# simulator is published, and that prose is internal. The field still appears,
# flagged so the page can say the description exists and was withheld.

require 'yaml'
require 'json'

ROOT = File.expand_path(ARGV[0] || File.join(Dir.home, 'code/factorial'))
BACKEND = File.join(ROOT, 'backend')

# --- What an accrual rule can actually reach, per state -----------------------
#
# The snapshot says what is REGISTERED. Registration is not reach: a rule reads
# an entity only where the evaluator BINDS it as an input. These are the binding
# states the simulator switches between.
#
# `runtime_inputs` mirrors `RUNTIME_INPUT_CATALOG`
# (timeoff/app/services/timeoff/factor/accrual_evaluator.rb). It is transcribed
# rather than parsed -- the constant is a Sorbet-typed literal inside a class, so
# there is no way to read it without booting Rails -- and `verify_inputs!` fails
# the dump if a key here no longer appears in that file, so a rename cannot pass
# silently.
RUNTIME_INPUTS = {
  'allowance' => { 'kind' => 'entity', 'entity' => 'timeoff.allowance',
                   'summary' => 'The counter being computed.' },
  'active_days' => { 'kind' => 'float', 'role' => 'accrual',
                     'summary' => 'Days active within the cycle; numerator of day proration.' },
  'cycle_days' => { 'kind' => 'float', 'role' => 'accrual',
                    'summary' => 'Total days in the cycle; the denominator.' },
  'tenure_adjustment_units' => { 'kind' => 'float', 'role' => 'tenure',
                                 'summary' => "The seniority bonus already sized, in the counter's unit." },
  'source_amount_units' => { 'kind' => 'float', 'role' => 'base_entitlement',
                             'summary' => 'Pre-computed accrual for a by_worked_time counter; 0.0 otherwise.' },
  'availability_fraction' => { 'kind' => 'float', 'role' => 'accrual',
                               'summary' => 'Portion of the cycle available so far. Always 1.0 in production today.' },
  'tenure_fraction' => { 'kind' => 'float', 'role' => 'tenure',
                         'summary' => 'Proration of the tenure bonus for a mid-cycle milestone.' },
  'hire_date' => { 'kind' => 'date', 'role' => 'accrual',
                   'summary' => 'NOT the hire date: cycle.start_at, the contract start clipped to the cycle and the policy timeline.' },
  'cycle_start_date' => { 'kind' => 'date', 'role' => 'accrual',
                          'summary' => 'First day of the cycle being computed.' },
  'cycle_end_date' => { 'kind' => 'date', 'role' => 'accrual',
                        'summary' => 'Last day of the cycle being computed.' },
  'tenure_date' => { 'kind' => 'date', 'role' => 'tenure',
                     'summary' => 'Seniority origin; falls back to contract start, so always present.' }
}.freeze

def verify_inputs!
  path = File.join(BACKEND, 'components/timeoff/app/services/timeoff/factor/accrual_evaluator.rb')
  source = File.read(path)
  missing = RUNTIME_INPUTS.keys.reject { |key| source.include?("'#{key}' =>") }
  return if missing.empty?

  abort "RUNTIME_INPUTS no longer match #{path} (renamed?): #{missing.join(', ')}"
end

# The accrual view of the registry, from `Timeoff::Factor::AllowedFactorEntities`
# on the branch of #113385. Reachability is not the registry's: this view narrows
# it three ways, and the simulator narrows it the same way or it would offer an
# author fields the save would refuse.
ACCRUAL_VIEW = {
  'roots' => {
    'allowance' => 'timeoff.allowance',
    'employee' => 'employees.employee',
    'contract' => 'contracts.contract_version'
  },
  # Only these may be landed on, however the graph leads there.
  'identifiers' => %w[
    api_core.company
    companies.legal_entity
    contracts.contract
    contracts.contract_status
    contracts.contract_version
    contracts.termination_type
    employees.employee
    locations.location
    teams.membership
    teams.team
    timeoff.allowance
    timeoff.leave
    timeoff.leave_type
    timeoff.policy
    timeoff.policy_assignment
  ].freeze,
  # Registered, and deliberately withheld from the accrual author.
  'withheld_fields' => { 'contracts.contract_version' => %w[salary_amount salary_frequency] },
  # Registered and allowed as entities, but not navigable from these parents.
  'hidden_associations' => {
    'employees.employee' => %w[leaves],
    'contracts.contract_version' => %w[job_catalog_level]
  }
}.freeze

BINDINGS = {
  'today' => {
    'label' => 'What arrives today',
    'entities' => { 'allowance' => 'timeoff.allowance' },
    'scalars' => RUNTIME_INPUTS.reject { |_, v| v['kind'] == 'entity' }.keys
  },
  'pr_113385' => {
    'label' => 'With #113385 — the employee and the contract',
    'entities' => { 'employee' => 'employees.employee', 'contract' => 'contracts.contract_version' },
    'scalars' => [],
    'caveat' =>
      "The contract bound is the version in force on the cycle's reference date, resolved in " \
        'Ruby by CycleContractVersion: CEL cannot pick a version out of the history, and ' \
        "is_reference is today's contract rather than the cycle's. One row per evaluation, so a " \
        'cycle containing two different contracts still cannot be split.'
  },
  'pr_113386' => {
    'label' => 'With #113386 — the rich catalog',
    'entities' => {},
    'scalars' => [],
    'describes_only' => true,
    'caveat' =>
      'Changes nothing about what a rule can reach: it changes what the author is told about ' \
        'it. Without it the schema lists bare field names, so One knows allowance.rounding ' \
        'exists but not that its values are decimals, half_day, quarters and round_up.'
  }
}.freeze

# Wall 3. Exposure does not touch this: it is a predicate on the counter itself.
ELIGIBILITY_GATE = {
  'source' => 'backend/components/timeoff/app/services/timeoff/factor/counter_program_assignment.rb:33',
  'conditions' => [
    'company feature DEV_FLEXIBLE_ACCRUAL_AUTHORITATIVE enabled',
    'allowance.base_units? — a by_worked_time counter never qualifies',
    'allowance.use_availability == all_days — any cadence disqualifies the counter'
  ]
}.freeze

# Wall 4. Where the computed number stops governing.
LANDING_GAPS = [
  { 'area' => 'booking',
    'note' => 'The booking gate re-runs legacy availability over the policy allowance and takes ' \
              'total_allowance from legacy; only .total is replaced. A rule that lowers the ' \
              'entitlement would still let people book against the legacy figure.' },
  { 'area' => 'carry_over',
    'note' => 'CalculateCycleCarryOver never consults Factor, so an assigned counter carries over ' \
              "legacy's number while showing CEL's balance all year." }
]. freeze

def snapshot
  YAML.unsafe_load_file(File.join(BACKEND, 'components/factor/registry_snapshot.yml'))
end

def resource_file(identifier)
  component, name = identifier.split('.', 2)
  dir = File.join(BACKEND, "components/#{component}/app/resources/#{component}")
  return nil unless Dir.exist?(dir)

  candidates = Dir[File.join(dir, '*.yml')]
  candidates.find { |p| File.basename(p, '.yml') == name } ||
    candidates.find { |p| File.basename(p, '.yml') == "#{name}s" }
end

def resource_doc(identifier)
  path = resource_file(identifier)
  return [nil, nil] unless path

  [YAML.unsafe_load_file(path), path.sub("#{ROOT}/", '')]
end

# Every property across the resource's raw_json_schema blocks. A resource can
# declare more than one (ContractVersion is overwritten by reference_contract.yml
# at apidoc build time), so the first definition of a property name wins.
def properties_for(doc)
  schemas = doc.dig('schema', 'raw_json_schema') || {}
  schemas.each_value.with_object({}) do |schema, out|
    (schema['properties'] || {}).each { |name, prop| out[name] ||= prop }
  end
end

def relationships_for(doc)
  (doc['relationships'] || []).to_h do |rel|
    [rel['name'].to_s, rel]
  end
end

def field_entry(name, sorbet_type, properties)
  prop = properties[name]
  description = prop && prop['description'].to_s.strip
  private_prose = Array(prop && prop['serialization_groups']).include?('private')

  entry = { 'type' => sorbet_type, 'nullable' => sorbet_type.to_s.start_with?('T.nilable') }
  if description.nil? || description.empty?
    entry['described'] = false
  elsif private_prose
    # The prose exists and disambiguates, but it is internal: say so, do not copy it.
    entry['described'] = true
    entry['description_withheld'] = true
  else
    entry['described'] = true
    entry['description'] = description.gsub(/\s+/, ' ')
  end
  entry
end

def association_entry(name, relationship)
  return { 'target' => nil, 'unresolved' => true } if relationship.nil?

  entry = { 'target' => relationship['resource_id'].to_s.delete_prefix(':') }
  entry['optional'] = true if relationship['optional']
  entry['kind'] = relationship['type'] if relationship['type']
  desc = relationship['description'].to_s.strip
  entry['description'] = desc.gsub(/\s+/, ' ') unless desc.empty?
  entry
end

entities = snapshot.fetch('entities').to_h do |identifier, entry|
  doc, source = resource_doc(identifier)
  properties = doc ? properties_for(doc) : {}
  relationships = doc ? relationships_for(doc) : {}

  fields = (entry['fields'] || {}).to_h do |name, sorbet_type|
    [name, field_entry(name, sorbet_type, properties)]
  end

  associations = (entry['associations'] || []).to_h do |name|
    [name, association_entry(name, relationships[name])]
  end

  resource_description = doc && doc['description'].to_s.strip
  built = { 'fields' => fields, 'associations' => associations }
  built['source'] = source if source
  if resource_description && !resource_description.empty?
    built['description'] = resource_description.gsub(/\s+/, ' ')
  end

  [identifier, built]
end

verify_inputs!

# Narrow every entity to the accrual view, and say so rather than dropping things
# silently: a field withheld from the author is a decision worth reading, and so is
# an association that exists and is not navigable from here.
entities.each do |identifier, entry|
  ACCRUAL_VIEW.fetch('withheld_fields').fetch(identifier, []).each do |field|
    entry['fields'][field]['withheld_from_accrual'] = true if entry['fields'].key?(field)
  end

  hidden = ACCRUAL_VIEW.fetch('hidden_associations').fetch(identifier, [])
  entry['associations'].each do |name, association|
    association['hidden_from_accrual'] = true if hidden.include?(name)
    association['target_not_allowed'] = true unless ACCRUAL_VIEW.fetch('identifiers').include?(association['target'])
  end

  entry['allowed_for_accrual'] = ACCRUAL_VIEW.fetch('identifiers').include?(identifier)
end

puts JSON.pretty_generate(
  'generated_from' => 'registry_snapshot.yml + app/resources/**/*.yml, narrowed by ' \
                      'Timeoff::Factor::AllowedFactorEntities (#113385)',
  'entity_count' => entities.size,
  'runtime_inputs' => RUNTIME_INPUTS,
  'bindings' => BINDINGS,
  'accrual_view' => ACCRUAL_VIEW,
  'eligibility_gate' => ELIGIBILITY_GATE,
  'landing_gaps' => LANDING_GAPS,
  'entities' => entities
)
