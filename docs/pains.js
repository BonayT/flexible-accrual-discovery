// The accrual pains database, as read on 8 September 2026 from the CX workspace
// table dated 14 August. Transcribed rather than generated: the Notion export
// quota blocks an automated pull, so refresh it by re-running this query and
// replacing the array wholesale.
//
//   SELECT "Pain ID (new system)", "Title", "Info Needed for the Rule",
//          "Business prio", "CMRR (€)", "Companies", "Countries"
//   FROM "collection://3535e6e0-51ee-8198-bf64-000be68e85b8"
//
// `facts` is the table's own "Info Needed for the Rule" column, which is what
// makes the pains usable here: it already says which data each rule needs.

export const PAINS = [
  { pain: '261', title: 'Inability to define accrual rules based on hire date', facts: ['Country', 'Hire date', 'Termination date'], prio: 'Prio 0', cmrr: 133719, companies: 531, countries: ['IT', 'PT', 'DACH', 'LATAM'] },
  { pain: '416', title: 'Lack of configurable accrual percentages per leave type', facts: ['In absence type', 'Country'], prio: 'Prio 0', cmrr: 91306, companies: 190, countries: ['FR', 'DACH'] },
  { pain: '1066', title: 'Vacation days rounding always rounds up instead of applying mathematical rounding', facts: ['Country'], prio: 'Prio 0', cmrr: 34477, companies: 36, countries: ['ES', 'PT', 'FR'] },
  { pain: '797', title: 'Not possible to duplicate a time off policy', facts: ['Full-time entitlement', '% Part time', 'Is Part Time'], prio: null, cmrr: 29464, companies: 76, countries: [] },
  { pain: '1981', title: "Accruals don't reflect true industry seniority across contracts", facts: [], prio: 'Prio 2', cmrr: 20259, companies: 6, countries: ['FR'] },
  { pain: '356', title: 'Part-time vacation must be calculated on days worked per week', facts: ['Full-time entitlement', 'Reference period', 'Is Part Time', 'Planning tool'], prio: 'Prio 0', cmrr: 19597, companies: 32, countries: [] },
  { pain: '352', title: 'Counters do not auto-adjust proportionally to mid-year contract changes', facts: ['Cycle start/end', 'Date of contract hours change', 'Current contract hours', 'Previous contract hours', 'Full-time entitlement', '% Part time', 'Is Part Time'], prio: 'Prio 0', cmrr: 18773, companies: 33, countries: ['FR'] },
  { pain: '1704', title: 'Cannot configure cycle durations of 9 months or longer', facts: [], prio: 'Prio 2', cmrr: 8062, companies: 17, countries: ['ZA'] },
  { pain: '613', title: 'Static vacation rules fail to auto-calculate entitlements for variable hours', facts: ['Current contract hours', 'Country', 'Hourly worker', 'Irregular schedules', 'Time worked in period', 'Reference period'], prio: 'Prio 1', cmrr: 7981, companies: 30, countries: ['DACH'] },
  { pain: '794', title: 'Counters over-grant full additional days on mid-cycle seniority', facts: ['Tenure date', 'Cycle start/end', 'Start date at company'], prio: 'Prio 0', cmrr: 7876, companies: 23, countries: ['IT'] },
  { pain: '1769', title: 'Cannot configure rolling cycles triggered by the first absence request', facts: ['Date of sick leave'], prio: 'Prio 3', cmrr: 5236, companies: 7, countries: ['UK'] },
  { pain: '1982', title: 'Cannot manage annual variations in accruals without data errors', facts: [], prio: null, cmrr: 4886, companies: 4, countries: [] },
  { pain: '1583', title: 'No rule-based leave allowances on number of dependent children', facts: [], prio: 'Prio 1', cmrr: 4058, companies: 9, countries: ['FR'] },
  { pain: '1726', title: 'Accrual rules lack quarterly and biennial options', facts: [], prio: 'Prio 3', cmrr: 3758, companies: 2, countries: [] },
  { pain: '1983', title: 'No multi-year accruals nor tenure-based termination payouts', facts: [], prio: 'Prio 1', cmrr: 3178, companies: 1, countries: ['PT'] },
  { pain: '769', title: 'Worked-time accruals cannot be configured in full days or months', facts: ['Time worked in period', 'Reference period'], prio: 'Prio 2', cmrr: 2279, companies: 12, countries: [] },
  { pain: '1529', title: 'No prorated annual leave for part-time employees based on hours', facts: [], prio: 'Prio 0', cmrr: 2319, companies: 1, countries: [] },
  { pain: '1755', title: 'Accruals reset on contract change, ignoring true seniority in the company', facts: [], prio: 'Prio 3', cmrr: 1639, companies: 2, countries: [] },
  { pain: '1870', title: 'No option to grant the full annual entitlement to second-half leavers', facts: [], prio: 'Prio 3', cmrr: 909, companies: 3, countries: [] },
  { pain: '1585', title: 'Tenure-based leave cannot have accrual rules of its own', facts: [], prio: 'Prio 0', cmrr: 649, companies: 4, countries: ['FR'] },
  { pain: '1442', title: 'Cannot configure 360-day cycles or apply proration to them', facts: [], prio: 'Prio 3', cmrr: 557, companies: 1, countries: [] },
  { pain: '1750', title: "No automatic calculation of French 'jours de fractionnement'", facts: ['Tenure date', 'Reference period', 'Approved absences'], prio: 'Prio 2', cmrr: 222, companies: 4, countries: ['FR'] },
  { pain: '1754', title: 'No automated age-based extra leave', facts: ['Employee age/birth date', 'Tenure date'], prio: 'Prio 1', cmrr: 185, companies: 4, countries: ['FR'] },
  { pain: '1576', title: 'No option to accrue all entitled days on the last day of the cycle', facts: [], prio: 'Prio 3', cmrr: 181, companies: 1, countries: ['FR'] },
  { pain: '1825', title: 'No Swiss-specific vacation entitlement reductions per labour law', facts: [], prio: 'Prio 3', cmrr: 0, companies: 9, countries: ['CH'] }
];
