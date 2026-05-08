// scenarios.js — All 10 customer pain scenarios for the playground

export const SCENARIOS = [
  {
    id: "pain1_italy",
    title: "Pain #1 — Italy: Hire date after 15th = 0 accrual",
    country: "🇮🇹 Italy",
    description: "If hired on/after 16th, accrue 0 for that month. Uses hire_date.day + year_month match.",
    employee: { hire_date: "2026-03-20", termination_date: null, country: "IT", name: "Luca Verdi" },
    program: {
      params: { monthly_base: 2.1667 },
      rule: { type: "accrue", amount: { type: "if", cond: { type: "and", operands: [
        { type: "eq", left: { type: "ref", path: "facts.hire_date.year_month" }, right: { type: "ref", path: "period.year_month" } },
        { type: "gt", left: { type: "ref", path: "facts.hire_date.day" }, right: { type: "const", value: 15 } }
      ]}, then: { type: "const", value: 0 }, else: { type: "param", name: "monthly_base" } } }
    }
  },
  {
    id: "pain1_portugal",
    title: "Pain #1 — Portugal: Full month not worked = 0",
    country: "🇵🇹 Portugal",
    description: "Terminated employee: months after termination accrue 0. Uses worked_full_month fact.",
    employee: { hire_date: "2024-01-10", termination_date: "2026-06-15", country: "PT", name: "João Silva" },
    program: {
      params: { monthly_base: 2 },
      rule: { type: "accrue", amount: { type: "if",
        cond: { type: "ref", path: "facts.worked_full_month" },
        then: { type: "param", name: "monthly_base" },
        else: { type: "const", value: 0 } } }
    }
  },
  {
    id: "pain2",
    title: "Pain #2 — DACH: Hours-based proportional accrual",
    country: "🇩🇪 DACH",
    description: "vacation = (actual_hours / reference_hours) × statutory_days/12. Part-time 20h/40h = 50%.",
    employee: { hire_date: "2023-06-01", termination_date: null, country: "DE", name: "Anna Müller", weekly_hours: 20, fte_ratio: 0.5 },
    program: {
      params: { statutory_annual_days: 30 },
      rule: { type: "accrue", amount: { type: "mul", operands: [
        { type: "div", operands: [
          { type: "ref", path: "facts.hours_worked_in_period" },
          { type: "ref", path: "facts.reference_period_hours" }
        ]},
        { type: "div", operands: [
          { type: "param", name: "statutory_annual_days" },
          { type: "const", value: 12 }
        ]}
      ]}}
    }
  },
  {
    id: "pain3",
    title: "Pain #3 — Contract change 40h→20h mid-year",
    country: "🇫🇷 France",
    description: "FT Jan-Jun, PT Jul-Dec. Accrual auto-adjusts via contract.weekly_hours fact.",
    employee: { hire_date: "2021-01-15", termination_date: null, country: "FR", name: "Sophie Laurent",
      contracts: [
        { weekly_hours: 40, fte_ratio: 1.0, start: "2021-01-15", end: "2026-06-30" },
        { weekly_hours: 20, fte_ratio: 0.5, start: "2026-07-01", end: null }
      ]
    },
    program: {
      params: { statutory_annual_days: 26, full_time_hours: 40 },
      rule: { type: "accrue", amount: { type: "mul", operands: [
        { type: "div", operands: [
          { type: "param", name: "statutory_annual_days" },
          { type: "const", value: 12 }
        ]},
        { type: "div", operands: [
          { type: "ref", path: "facts.contract.weekly_hours" },
          { type: "param", name: "full_time_hours" }
        ]}
      ]}}
    }
  },
  {
    id: "pain4_france",
    title: "Pain #4 — France: Sick leave → 80% accrual rate",
    country: "🇫🇷 France",
    description: "Non-work-related sick leave: accrue 2.0/month instead of 2.5. Uses exists + absence type.",
    employee: { hire_date: "2020-03-15", termination_date: null, country: "FR", name: "Marie Dupont",
      sick_months: [3, 4] },
    program: {
      params: { full_rate: 2.5, sick_rate: 2.0 },
      rule: { type: "accrue", amount: { type: "if",
        cond: { type: "exists", in: { type: "ref", path: "facts.absences_in_period" }, binding: "absence",
          where: { type: "eq", left: { type: "ref", path: "absence.type" }, right: { type: "const", value: "sick_non_work_related" } } },
        then: { type: "param", name: "sick_rate" },
        else: { type: "param", name: "full_rate" } } }
    }
  },
  {
    id: "pain4_dach",
    title: "Pain #4 — DACH: Extended sick → 0 accrual",
    country: "🇩🇪 DACH",
    description: "Extended sick leave (>6 weeks): zero accrual for those months.",
    employee: { hire_date: "2019-01-01", termination_date: null, country: "DE", name: "Hans Schmidt",
      sick_months: [3, 4] },
    program: {
      params: { full_rate: 2.5 },
      rule: { type: "accrue", amount: { type: "if",
        cond: { type: "exists", in: { type: "ref", path: "facts.absences_in_period" }, binding: "absence",
          where: { type: "eq", left: { type: "ref", path: "absence.type" }, right: { type: "const", value: "sick_non_work_related" } } },
        then: { type: "const", value: 0 },
        else: { type: "param", name: "full_rate" } } }
    }
  },
  {
    id: "pain5_spain",
    title: "Pain #5 — Spain: Mathematical rounding to full days",
    country: "🇪🇸 Spain",
    description: "1.833 → nearest full day = 2. Standard mathematical rounding (≥0.5 rounds up).",
    employee: { hire_date: "2022-01-10", termination_date: null, country: "ES", name: "Carlos García" },
    program: {
      params: { monthly_base: 1.833 },
      rule: { type: "accrue", amount: { type: "round",
        value: { type: "param", name: "monthly_base" }, mode: "nearest", step: 1 } }
    }
  },
  {
    id: "pain5_portugal",
    title: "Pain #5 — Portugal: Always round up to full days",
    country: "🇵🇹 Portugal",
    description: "2.3 → always rounds up to 3. Ceiling rounding.",
    employee: { hire_date: "2022-01-10", termination_date: null, country: "PT", name: "Ana Oliveira" },
    program: {
      params: { monthly_base: 2.3 },
      rule: { type: "accrue", amount: { type: "round",
        value: { type: "param", name: "monthly_base" }, mode: "up", step: 1 } }
    }
  },
  {
    id: "pain6",
    title: "Pain #6 — Accrual per days worked per week",
    country: "🌍 Generic",
    description: "Part-timer 3 days/week: (3/5) × 23 annual = 13.8 days. Uses contract.days_per_week.",
    employee: { hire_date: "2023-01-01", termination_date: null, country: "DE", name: "Emma Weber", days_per_week: 3 },
    program: {
      params: { annual_days: 23, full_time_days_per_week: 5 },
      rule: { type: "accrue", amount: { type: "mul", operands: [
        { type: "div", operands: [
          { type: "ref", path: "facts.contract.days_per_week" },
          { type: "param", name: "full_time_days_per_week" }
        ]},
        { type: "div", operands: [
          { type: "param", name: "annual_days" },
          { type: "const", value: 12 }
        ]}
      ]}}
    }
  },
  {
    id: "pain7",
    title: "Pain #7 — Italy: Tenure milestone mid-cycle (5yr → extra)",
    country: "🇮🇹 Italy",
    description: "5-year seniority reached in June → +0.167/month from June onwards. Uses tenure_years case.",
    employee: { hire_date: "2021-06-15", termination_date: null, country: "IT", name: "Giuseppe Marino" },
    program: {
      params: { base_monthly: 2.1667 },
      rule: { type: "accrue", amount: { type: "add", operands: [
        { type: "param", name: "base_monthly" },
        { type: "case", branches: [
          { when: { type: "gte", left: { type: "ref", path: "facts.tenure_years_at_period_end" }, right: { type: "const", value: 10 } },
            then: { type: "const", value: 0.333 } },
          { when: { type: "gte", left: { type: "ref", path: "facts.tenure_years_at_period_end" }, right: { type: "const", value: 5 } },
            then: { type: "const", value: 0.167 } }
        ], else: { type: "const", value: 0 } }
      ]}}
    }
  },
  {
    id: "pain9",
    title: "Pain #9 — Part-time proportional accrual (60% FTE)",
    country: "🇩🇪 Germany",
    description: "Same pattern as #2/#6: monthly_base × fte_ratio. Confirms no new AST capability needed.",
    employee: { hire_date: "2022-01-01", termination_date: null, country: "DE", name: "Clara Hofmann", fte_ratio: 0.6 },
    program: {
      params: { full_time_monthly: 2.5 },
      rule: { type: "accrue", amount: { type: "mul", operands: [
        { type: "param", name: "full_time_monthly" },
        { type: "ref", path: "facts.contract.fte_ratio" }
      ]}}
    }
  },
  {
    id: "pain8",
    title: "Pain #8 — UK: Rolling 12-month sick entitlement ⚠️",
    country: "🇬🇧 UK",
    description: "Requires cross-period state (balance_rule). Runtime manages rolling window, AST accrues normally.",
    employee: { hire_date: "2022-01-01", termination_date: null, country: "UK", name: "James Wilson" },
    needsBalanceRule: true,
    balanceRule: { type: "rolling", window_months: 12 },
    program: {
      params: { monthly_entitlement: 2.333 },
      rule: { type: "accrue", amount: { type: "param", name: "monthly_entitlement" } }
    }
  },
  {
    id: "pain10",
    title: "Pain #10 — Overtime balance cap at 40h ⚠️",
    country: "🇩🇪 Germany",
    description: "Requires cross-period state (balance_rule). Stops accruing at cap via accumulated_balance fact.",
    employee: { hire_date: "2020-01-01", termination_date: null, country: "DE", name: "Martin Berger" },
    needsBalanceRule: true,
    balanceRule: { type: "capped", cap: 40 },
    program: {
      params: { monthly_overtime_accrual: 5 },
      rule: { type: "accrue", amount: { type: "min", operands: [
        { type: "param", name: "monthly_overtime_accrual" },
        { type: "max", operands: [
          { type: "const", value: 0 },
          { type: "sub", operands: [
            { type: "const", value: 40 },
            { type: "ref", path: "facts.accumulated_balance" }
          ]}
        ]}
      ]}}
    }
  }
];
