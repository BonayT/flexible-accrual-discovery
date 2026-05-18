// scenarios.js — All 10 customer pain scenarios for the playground

export const SCENARIOS = [
  {
    id: "pain1_italy",
    title: "Pain #1 — Italy: Hire date after 15th = 0 accrual",
    country: "🇮🇹 Italy",
    description: "Pre-hire months → 0. Hire month: if hired on/after day_threshold → 0, before → full. Post-hire → full.",
    employee: { hire_date: "2026-03-20", termination_date: null, country: "IT", name: "Luca Verdi" },
    program: {
      params: { monthly_base: 2.1667, day_threshold: 15 },
      rule: { type: "accrue", amount: { type: "case", branches: [
        { when: { type: "lt", left: { type: "ref", path: "period.year_month" }, right: { type: "ref", path: "facts.hire_date.year_month" } },
          then: { type: "const", value: 0 } },
        { when: { type: "and", operands: [
          { type: "eq", left: { type: "ref", path: "period.year_month" }, right: { type: "ref", path: "facts.hire_date.year_month" } },
          { type: "gt", left: { type: "ref", path: "facts.hire_date.day" }, right: { type: "param", name: "day_threshold" } }
        ]}, then: { type: "const", value: 0 } }
      ], else: { type: "param", name: "monthly_base" } } }
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
  },

  // ─── E2E Cases: TransExpress Logistics S.L. ───────────────────────────────

  {
    id: "e2e_case1",
    title: "E2E Case 1 — Tenure milestone mid-cycle (Coslada)",
    country: "🇪🇸 Spain",
    description: "Carlos Ruiz, Coslada warehouse. 23 days/year base + 1 day per 5-year tenure milestone (max +3). Reaches 5y in Jun 2024 → base jumps to 24. Round to nearest half day.",
    isE2E: true,
    employee: { hire_date: "2019-06-15", termination_date: null, country: "ES", name: "Carlos Ruiz", weekly_hours: 40, fte_ratio: 1.0, days_per_week: 5 },
    evaluationYear: 2024,
    mermaid: `graph TD
    ROOT[accrue] -->|amount| IF[if]
    IF -->|cond| WFM["ref 'worked_full_month'"]
    IF -->|else| ZERO[const 0]
    IF -->|then| ROUND["round half_up step=0.5"]
    ROUND -->|value| DIV[div]
    DIV -->|op1| ADD[add]
    DIV -->|op2| TWELVE[const 12]
    ADD -->|op1| BASE["param 'base_days' = 23"]
    ADD -->|op2| MIN[min]
    MIN -->|op1| MUL[mul]
    MIN -->|op2| MAX_B["param 'max_tenure_bonus' = 3"]
    MUL -->|op1| BONUS["param 'tenure_bonus_per_milestone' = 1"]
    MUL -->|op2| TDIV[div]
    TDIV -->|op1| TENURE["ref 'tenure_years_at_period_end'"]
    TDIV -->|op2| MILESTONE["param 'tenure_milestone_years' = 5"]`,
    program: {
      params: { base_days: 23, tenure_bonus_per_milestone: 1, tenure_milestone_years: 5, max_tenure_bonus: 3, rounding_step: 0.5 },
      rule: { type: "accrue", amount: { type: "round", mode: "half_up", step: { type: "param", name: "rounding_step" }, value: {
        type: "div", operands: [
          { type: "add", operands: [
            { type: "param", name: "base_days" },
            { type: "min", operands: [
              { type: "mul", operands: [
                { type: "param", name: "tenure_bonus_per_milestone" },
                { type: "div", operands: [
                  { type: "floor", value: { type: "div", operands: [{ type: "ref", path: "facts.tenure_years_at_period_end" }, { type: "param", name: "tenure_milestone_years" }] } },
                  { type: "const", value: 1 }
                ]}
              ]},
              { type: "param", name: "max_tenure_bonus" }
            ]}
          ]},
          { type: "const", value: 12 }
        ]
      }}}
    }
  },
  {
    id: "e2e_case2",
    title: "E2E Case 2 — Part-time + contract change + sick leave (Barcelona)",
    country: "🇪🇸 Spain",
    description: "Laura Martínez, Barcelona. 24 days/year. Part-time (20h) Jan–Jun, full-time (40h) Jul–Dec. March: 10 sick days → 80% accrual rate.",
    isE2E: true,
    employee: { hire_date: "2022-03-01", termination_date: null, country: "ES", name: "Laura Martínez",
      contracts: [
        { weekly_hours: 20, fte_ratio: 0.5, start: "2022-03-01", end: "2024-06-30" },
        { weekly_hours: 40, fte_ratio: 1.0, start: "2024-07-01", end: null }
      ],
      sick_months: [3]
    },
    evaluationYear: 2024,
    mermaid: `graph TD
    ROOT[accrue] -->|amount| IF1[if]
    IF1 -->|cond| WFM["ref 'worked_full_month'"]
    IF1 -->|else| ZERO[const 0]
    IF1 -->|then| IF2[if]
    IF2 -->|cond| EXISTS["exists in 'absences_in_period'"]
    EXISTS -->|where| EQ["absence.type == 'sick'"]
    IF2 -->|then| MUL_SICK["mul (sick path)"]
    MUL_SICK -->|op1| RATIO["hours_worked / reference_hours"]
    MUL_SICK -->|op2| MONTHLY["base_days / 12"]
    MUL_SICK -->|op3| RATE["param 'sick_accrual_rate' = 0.8"]
    IF2 -->|else| MUL_NORMAL["mul (normal path)"]
    MUL_NORMAL -->|op1| FTE["ref 'contract.fte_ratio'"]
    MUL_NORMAL -->|op2| MONTHLY2["base_days / 12"]`,
    program: {
      params: { base_days: 24, sick_accrual_rate: 0.8 },
      rule: { type: "accrue", amount: { type: "if",
        cond: { type: "ref", path: "facts.worked_full_month" },
        then: { type: "if",
          cond: { type: "exists", in: { type: "ref", path: "facts.absences_in_period" }, binding: "absence",
            where: { type: "eq", left: { type: "ref", path: "absence.type" }, right: { type: "const", value: "sick_non_work_related" } } },
          then: { type: "mul", operands: [
            { type: "div", operands: [{ type: "ref", path: "facts.hours_worked_in_period" }, { type: "ref", path: "facts.reference_period_hours" }] },
            { type: "div", operands: [{ type: "param", name: "base_days" }, { type: "const", value: 12 }] },
            { type: "param", name: "sick_accrual_rate" }
          ]},
          else: { type: "mul", operands: [
            { type: "ref", path: "facts.contract.fte_ratio" },
            { type: "div", operands: [{ type: "param", name: "base_days" }, { type: "const", value: 12 }] }
          ]}
        },
        else: { type: "const", value: 0 }
      }}
    }
  },
  {
    id: "e2e_case3",
    title: "E2E Case 3 — Overtime cap at 40h (Valencia)",
    country: "🇪🇸 Spain",
    description: "Miguel Fernández, Valencia supervisor. Overtime → compensatory time at 1.5×. Cap at 40h accumulated. Starts Oct at 35h. Nov: capped. Dec: fully capped.",
    isE2E: true,
    needsBalanceRule: true,
    balanceRule: { type: "capped", cap: 40 },
    employee: { hire_date: "2020-01-10", termination_date: null, country: "ES", name: "Miguel Fernández", weekly_hours: 40, fte_ratio: 1.0, days_per_week: 5,
      overtime_months: { 1: 5, 2: 5, 3: 3, 4: 4, 5: 3, 6: 0, 7: 2, 8: 3, 9: 5, 10: 5, 11: 5, 12: 5 }
    },
    evaluationYear: 2024,
    mermaid: `graph TD
    ROOT[accrue] -->|amount| IF[if]
    IF -->|cond| GT["hours_worked > reference_hours"]
    IF -->|then| MUL[mul]
    MUL -->|op1| SUB["hours_worked - reference_hours"]
    MUL -->|op2| RATE["param 'overtime_conversion_rate' = 1.5"]
    IF -->|else| ZERO[const 0]
    CAP["BalanceEvaluator cap=40"]
    MUL --> CAP`,
    program: {
      params: { overtime_conversion_rate: 1.5 },
      rule: { type: "accrue", amount: { type: "if",
        cond: { type: "gt", left: { type: "ref", path: "facts.hours_worked_in_period" }, right: { type: "ref", path: "facts.reference_period_hours" } },
        then: { type: "mul", operands: [
          { type: "sub", operands: [{ type: "ref", path: "facts.hours_worked_in_period" }, { type: "ref", path: "facts.reference_period_hours" }] },
          { type: "param", name: "overtime_conversion_rate" }
        ]},
        else: { type: "const", value: 0 }
      }}
    }
  },
  {
    id: "e2e_case4",
    title: "E2E Case 4 — Same program, different params per workplace",
    country: "🇪🇸 Spain",
    description: "Pedro (Coslada, 23d) vs Ana (Valencia, 25d). Same AST program, params differ by workplace dimension. Both 3y tenure, no milestone bonus yet.",
    isE2E: true,
    employee: { hire_date: "2021-01-15", termination_date: null, country: "ES", name: "Pedro López (Coslada)", weekly_hours: 40, fte_ratio: 1.0, days_per_week: 5 },
    evaluationYear: 2024,
    mermaid: `graph TD
    ROOT[accrue] -->|amount| IF[if]
    IF -->|cond| WFM["ref 'worked_full_month'"]
    IF -->|else| ZERO[const 0]
    IF -->|then| DIV[div]
    DIV -->|op1| ADD[add]
    DIV -->|op2| TWELVE[const 12]
    ADD -->|op1| BASE["param 'base_days' = ⚡ varies"]
    ADD -->|op2| MIN[min]
    MIN -->|op1| MUL[mul]
    MIN -->|op2| MAX_B["param 'max_tenure_bonus' = 3"]
    MUL -->|op1| BONUS["1"]
    MUL -->|op2| TDIV["floor(tenure / 5)"]
    style BASE fill:#ff9,stroke:#333`,
    variants: [
      { label: "Pedro (Coslada)", params: { base_days: 23, tenure_bonus_per_milestone: 1, tenure_milestone_years: 5, max_tenure_bonus: 3 }, employee: { hire_date: "2021-01-15", termination_date: null, country: "ES", name: "Pedro López (Coslada)", weekly_hours: 40, fte_ratio: 1.0, days_per_week: 5 } },
      { label: "Ana (Valencia)", params: { base_days: 25, tenure_bonus_per_milestone: 1, tenure_milestone_years: 5, max_tenure_bonus: 3 }, employee: { hire_date: "2021-01-15", termination_date: null, country: "ES", name: "Ana García (Valencia)", weekly_hours: 40, fte_ratio: 1.0, days_per_week: 5 } }
    ],
    program: {
      params: { base_days: 23, tenure_bonus_per_milestone: 1, tenure_milestone_years: 5, max_tenure_bonus: 3 },
      rule: { type: "accrue", amount: { type: "div", operands: [
        { type: "add", operands: [
          { type: "param", name: "base_days" },
          { type: "min", operands: [
            { type: "mul", operands: [
              { type: "param", name: "tenure_bonus_per_milestone" },
              { type: "floor", value: { type: "div", operands: [{ type: "ref", path: "facts.tenure_years_at_period_end" }, { type: "param", name: "tenure_milestone_years" }] } }
            ]},
            { type: "param", name: "max_tenure_bonus" }
          ]}
        ]},
        { type: "const", value: 12 }
      ]}}
    }
  }
];
