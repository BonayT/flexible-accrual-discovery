# End-to-End Cases — Flexible Accrual (Approach C)

> **Purpose**: Define 4 realistic cases that exercise the full pipeline:
> Employee → AccrualFactBuilder → AST Evaluator → BalanceEvaluator → Adjustment output.
>
> These cases serve as **W2 (Real Fact Builder) acceptance criteria**.
> Each case specifies exactly which facts are needed, how the AST program uses them,
> and what the expected month-by-month output is.

## Company: TransExpress Logistics S.L.

- **Industry**: Logistics / Transport
- **Locations**: Coslada (Madrid), Barcelona, Valencia
- **Convenio colectivo**: Convenio de Transporte de Mercancías
- **Accrual cycle**: Calendar year (Jan 1 – Dec 31)
- **Base entitlement by workplace**:
  - Coslada: 23 days/year
  - Barcelona: 24 days/year
  - Valencia: 25 days/year
- **Tenure bonus**: +1 day/year for each 5-year milestone (up to +3 days max)

---

## Case 1: Operario Almacén Coslada — Tenure milestone mid-cycle

**Pains exercised**: #1 (hire date pro-rata), #5 (rounding), #7 (tenure milestone)

### Employee

| Field | Value |
|-------|-------|
| Name | Carlos Ruiz |
| Hired on | 2019-06-15 |
| Workplace | Coslada |
| Contract | Full-time, 40h/week, 5 days/week |
| FTE ratio | 1.0 |
| Terminated | — |

### User rule (natural language)

> "23 vacation days per year. For every 5 years of tenure, add 1 extra day, up to a maximum of 3 extra days. Round to the nearest half day."

### Scenario

Cycle 2024. Carlos reaches **5 years tenure** on 2024-06-15.
Before that milestone: base = 23 days. After milestone: base = 24 days (+1 bonus).
Monthly accrual changes mid-cycle.

### AST Program (compiled from user rule)

```json
{
  "params": {
    "base_days": 23,
    "tenure_bonus_per_milestone": 1,
    "tenure_milestone_years": 5,
    "max_tenure_bonus": 3,
    "rounding_mode": "half_up",
    "rounding_step": 0.5
  },
  "requires": ["tenure_years_at_period_end", "tenure_milestone_reached_in_cycle", "worked_full_month"],
  "rule": {
    "type": "if",
    "cond": { "type": "ref", "path": "worked_full_month" },
    "then": {
      "type": "accrue",
      "amount": {
        "type": "round",
        "mode": { "type": "param", "name": "rounding_mode" },
        "step": { "type": "param", "name": "rounding_step" },
        "value": {
          "type": "div",
          "operands": [
            {
              "type": "add",
              "operands": [
                { "type": "param", "name": "base_days" },
                {
                  "type": "min",
                  "operands": [
                    {
                      "type": "mul",
                      "operands": [
                        { "type": "param", "name": "tenure_bonus_per_milestone" },
                        {
                          "type": "div",
                          "operands": [
                            { "type": "ref", "path": "tenure_years_at_period_end" },
                            { "type": "param", "name": "tenure_milestone_years" }
                          ]
                        }
                      ]
                    },
                    { "type": "param", "name": "max_tenure_bonus" }
                  ]
                }
              ]
            },
            { "type": "const", "value": 12 }
          ]
        }
      }
    },
    "else": { "type": "accrue", "amount": { "type": "const", "value": 0 } }
  }
}
```

### Facts (generic) needed per period

| Fact | Source |
|------|--------|
| `hired_on` | Employee record |
| `tenure_years_at_period_end` | `(period_end - hired_on) / 365.25` |
| `worked_full_month` | Not terminated & hired before period end |
| `tenure_milestone_reached_in_cycle` | Floor(tenure_end) > Floor(tenure_start) |

### Expected output

| Month | tenure_years (floor) | effective_base | monthly_accrual | rounded (step=0.5) |
|-------|---------------------|----------------|-----------------|-------------------|
| Jan | 4 | 23 | 1.916… | 2.0 |
| Feb | 4 | 23 | 1.916… | 2.0 |
| Mar | 4 | 23 | 1.916… | 2.0 |
| Apr | 4 | 23 | 1.916… | 2.0 |
| May | 4 | 23 | 1.916… | 2.0 |
| Jun | 5 | 24 | 2.0 | 2.0 |
| Jul | 5 | 24 | 2.0 | 2.0 |
| Aug | 5 | 24 | 2.0 | 2.0 |
| Sep | 5 | 24 | 2.0 | 2.0 |
| Oct | 5 | 24 | 2.0 | 2.0 |
| Nov | 5 | 24 | 2.0 | 2.0 |
| Dec | 5 | 24 | 2.0 | 2.0 |
| **Total** | | | | **24.0** |

> Note: Without tenure bonus the total would be 23.0. The mid-cycle milestone adds
> exactly the 1 extra day (distributed across Jun–Dec as higher monthly).

---

## Case 2: Administrativa Barcelona — Part-time + contract change + sick leave

**Pains exercised**: #2 (part-time proportionality), #3 (contract change mid-cycle), #4 (sick leave impact), #9 (hours-based accrual)

### Employee

| Field | Value |
|-------|-------|
| Name | Laura Martínez |
| Hired on | 2022-03-01 |
| Workplace | Barcelona |
| Terminated | — |

### Contracts

| # | Start | End | Weekly hours | Days/week | FTE ratio | Part-time |
|---|-------|-----|-------------|-----------|-----------|-----------|
| 1 | 2022-03-01 | 2024-06-30 | 20 | 5 | 0.5 | true |
| 2 | 2024-07-01 | — | 40 | 5 | 1.0 | false |

### Leaves

| Type | Start | End | Note |
|------|-------|-----|------|
| sick | 2024-03-11 | 2024-03-22 | 10 working days in March |

### User rule (natural language)

> "24 vacation days per year, proportional to hours worked. Part-time employees accrue in proportion to their schedule. During sick leave, accrue at 80% of effective hours."

### Scenario

- Jan–Jun: Part-time (20h/week). Hours-based accrual = (hours_worked / reference_hours) × base.
- March: 10 sick days → reduced hours worked. Sick accrual at 80% rate.
- Jul–Dec: Full-time switch. FTE = 1.0, full monthly accrual.

### AST Program (compiled from user rule)

```json
{
  "params": {
    "base_days": 24,
    "sick_accrual_rate": 0.8
  },
  "requires": ["hours_worked_in_period", "reference_period_hours", "contract.fte_ratio", "absences_in_period", "worked_full_month"],
  "rule": {
    "type": "if",
    "cond": { "type": "ref", "path": "worked_full_month" },
    "then": {
      "type": "accrue",
      "amount": {
        "type": "if",
        "cond": {
          "type": "exists",
          "in": { "type": "ref", "path": "absences_in_period" },
          "binding": "absence",
          "where": { "type": "eq", "left": { "type": "ref", "path": "absence.type" }, "right": { "type": "const", "value": "sick" } }
        },
        "then": {
          "type": "mul",
          "operands": [
            {
              "type": "div",
              "operands": [
                { "type": "ref", "path": "hours_worked_in_period" },
                { "type": "ref", "path": "reference_period_hours" }
              ]
            },
            { "type": "div", "operands": [{ "type": "param", "name": "base_days" }, { "type": "const", "value": 12 }] },
            { "type": "param", "name": "sick_accrual_rate" }
          ]
        },
        "else": {
          "type": "mul",
          "operands": [
            { "type": "ref", "path": "contract.fte_ratio" },
            { "type": "div", "operands": [{ "type": "param", "name": "base_days" }, { "type": "const", "value": 12 }] }
          ]
        }
      }
    },
    "else": { "type": "accrue", "amount": { "type": "const", "value": 0 } }
  }
}
```

### Facts needed per period

| Fact | Source | Type |
|------|--------|------|
| `contract.fte_ratio` | Active contract in period | Generic |
| `contract.weekly_hours` | Active contract | Generic |
| `hours_worked_in_period` | (working_days - leave_days) × daily_hours | Specific |
| `reference_period_hours` | working_days × 8h (full-time reference) | Specific |
| `absences_in_period` | Leaves overlapping period | Specific |
| `worked_full_month` | Hired before period end & not terminated | Generic |

### Expected output

| Month | FTE | Hours worked | Ref hours | Has sick? | Monthly accrual |
|-------|-----|-------------|-----------|-----------|-----------------|
| Jan | 0.5 | 88.0 | 176.0 | no | 1.0 |
| Feb | 0.5 | 80.0 | 160.0 | no | 1.0 |
| Mar | 0.5 | 48.0 | 176.0 | **yes** | 0.436 |
| Apr | 0.5 | 88.0 | 176.0 | no | 1.0 |
| May | 0.5 | 88.0 | 176.0 | no | 1.0 |
| Jun | 0.5 | 80.0 | 160.0 | no | 1.0 |
| Jul | 1.0 | — | — | no | 2.0 |
| Aug | 1.0 | — | — | no | 2.0 |
| Sep | 1.0 | — | — | no | 2.0 |
| Oct | 1.0 | — | — | no | 2.0 |
| Nov | 1.0 | — | — | no | 2.0 |
| Dec | 1.0 | — | — | no | 2.0 |
| **Total** | | | | | **~17.4** |

> Part-time half-year (6 × 1.0 ≈ 5.4 with March reduction) + full-time half (6 × 2.0 = 12.0) = ~17.4 days.
> Without contract change: full year at 0.5 FTE would give 12 days.

---

## Case 3: Supervisor Valencia — Overtime cap at 40h (rolling balance)

**Pains exercised**: #8 (rolling window), #10 (balance cap)

### Employee

| Field | Value |
|-------|-------|
| Name | Miguel Fernández |
| Hired on | 2020-01-10 |
| Workplace | Valencia |
| Contract | Full-time, 40h/week |
| Terminated | — |

### User rule (natural language)

> "Overtime hours are converted to compensatory time off at 1.5× rate. Maximum 40 hours of compensatory time can be accumulated per year. Once the cap is reached, no further overtime converts to time off."

### Scenario

Miguel earns compensatory time (overtime hours as time-off).
Per convenio, the cap is **40 hours** per rolling 12-month window.
He's been earning steadily: by October 2024 he's at 35h accumulated.
November and December each generate 5h overtime → cap should kick in at December.

### AST Program (overtime to time-off conversion)

```json
{
  "params": {
    "overtime_conversion_rate": 1.5
  },
  "balance_rule": {
    "type": "capped",
    "cap": 40
  },
  "requires": ["hours_worked_in_period", "reference_period_hours"],
  "rule": {
    "type": "accrue",
    "amount": {
      "type": "if",
      "cond": {
        "type": "gt",
        "left": { "type": "ref", "path": "hours_worked_in_period" },
        "right": { "type": "ref", "path": "reference_period_hours" }
      },
      "then": {
        "type": "mul",
        "operands": [
          {
            "type": "sub",
            "operands": [
              { "type": "ref", "path": "hours_worked_in_period" },
              { "type": "ref", "path": "reference_period_hours" }
            ]
          },
          { "type": "param", "name": "overtime_conversion_rate" }
        ]
      },
      "else": { "type": "const", "value": 0 }
    }
  }
}
```

### Balance runtime behavior

> **Note**: The `balance_rule` key shown in the AST above is a simplified format
> used in our discovery. The upstream POC now uses a richer `BalanceEvaluator` with
> bucket-based ledger, FIFO/LIFO consumption, and expiration. The upstream format is:
> ```json
> "balance": { "carry_over": { "max": 40 }, "consumption": <AST node> }
> ```
> For W2 purposes, the key requirement is unchanged: the FactBuilder provides
> `hours_worked_in_period` and `reference_period_hours`; the runtime injects
> `accumulated_balance` before each evaluation.

```
accumulated = 35.0  (from Jan–Oct)
November: raw = 5h × 1.5 = 7.5h → effective = min(7.5, 40 - 35) = 5.0h → accumulated = 40.0
December: raw = 5h × 1.5 = 7.5h → effective = min(7.5, 40 - 40) = 0.0h → accumulated = 40.0 (capped)
```

### Expected output (Nov–Dec focus)

| Month | Overtime hours | Raw accrual | Cap remaining | Effective accrual | Accumulated |
|-------|---------------|-------------|---------------|-------------------|-------------|
| Oct | — | — | 5.0 | — | 35.0 |
| Nov | 5.0 | 7.5 | 5.0 | **5.0** | 40.0 |
| Dec | 5.0 | 7.5 | 0.0 | **0.0** | 40.0 |

### W2 FactBuilder requirements for this case

- Must receive `accumulated_balance` from BalanceRule (injected, not computed by FactBuilder)
- Must provide `hours_worked_in_period` from actual clock-in data or shifts
- Must provide `reference_period_hours` from contract + calendar

---

## Case 4: Same role, different workplace — Dimension-driven parameter differences

**Pains exercised**: Demonstrates that **same AST program** with **different params** produces correct results per workplace.

### Employees

| Name | Workplace | Base days (param) | Tenure bonus |
|------|-----------|-------------------|--------------|
| Pedro López | Coslada | 23 | +1 at 5y |
| Ana García | Valencia | 25 | +1 at 5y |

Both are Operarios, hired same day (2021-01-15), full-time, no leaves.

### User rule (natural language)

> "Same accrual rules apply to all Operarios regardless of workplace. The base entitlement is defined per workplace: Coslada gets 23 days, Valencia gets 25 days."

### Scenario

Cycle 2024. Both have 3 years tenure (no milestone).
Same AST program, different `base_days` param based on workplace dimension.

### AST Program

Same as Case 1, but with different params:

- Pedro (Coslada): `"base_days": 23` → monthly = 23/12 = 1.916… → rounded = 2.0 → annual = 24.0? No — rounding step 0.5:
  - 23/12 = 1.9166 → nearest 0.5 = 2.0 → total = 24.0
  - But tenure floor(3/5) = 0 bonus → effective_base = 23 → 23/12 = 1.916 → round(half_up, 0.5) = 2.0 → 24.0
  - **Issue**: Rounding inflates. With `rounding_mode: "down"` → 1.5 × 12 = 18.0. Let's use no rounding for this case.

Let's simplify — no rounding for Case 4 to isolate the dimension effect:

- Pedro (Coslada): `"base_days": 23` → 23/12 = 1.9166… per month → total ≈ 23.0
- Ana (Valencia): `"base_days": 25` → 25/12 = 2.0833… per month → total ≈ 25.0

### Key point for W2

The **FactBuilder doesn't know about params** — it only builds facts from employee/contract data.
The **params come from the policy assignment** which is resolved by the Rules Engine based on dimensions (workplace, contract type, role).

```
┌─────────────┐     dimensions      ┌──────────────────┐
│  Employee   │ ──────────────────→  │ Rules Engine     │
│  (Pedro)    │  workplace=Coslada   │ resolves policy  │
└─────────────┘                      │ → params         │
                                     │   base_days: 23  │
       │                             └────────┬─────────┘
       │ models                               │ params
       ▼                                      ▼
┌──────────────┐                    ┌──────────────────┐
│ FactBuilder  │ ──── facts ──────→ │ AST Evaluator    │
│ (W2)        │                     │ (same program)   │
└──────────────┘                    └──────────────────┘
```

### Expected output

| Employee | Workplace | base_days | Monthly | Annual total |
|----------|-----------|-----------|---------|--------------|
| Pedro | Coslada | 23 | 1.9166… | 23.0 |
| Ana | Valencia | 25 | 2.0833… | 25.0 |

---

## Summary: W2 FactBuilder Requirements

Based on all 4 cases, the FactBuilder must:

### Generic facts (always built)

| Fact | Source |
|------|--------|
| `hire_date` | `Employee#hired_on` |
| `termination_date` | `Employee#terminated_on` |
| `worked_full_month` | Derived: not terminated & hired before period end |
| `tenure_years_at_period_end` | `(period_end - hire_date) / 365.25` |
| `tenure_years_at_period_start` | `(period_start - hire_date) / 365.25` |
| `tenure_milestone_reached_in_cycle` | Floor crossover check |
| `contract.weekly_hours` | Active `ContractVersion#weekly_hours` |
| `contract.days_per_week` | Active `ContractVersion#days_per_week` |
| `contract.fte_ratio` | Active `ContractVersion#fte_ratio` |
| `contract.is_part_time` | Derived from FTE < 1.0 or contract flag |
| `country` | `Employee#country` or `LegalEntity#country` |

### Specific facts (on-demand, declared in `requires`)

| Fact | Source | Used by |
|------|--------|---------|
| `absences_in_period` | `Leave` records overlapping period | Case 2 |
| `hours_worked_in_period` | (working_days - leave_days) × daily_hours | Cases 2, 3 |
| `reference_period_hours` | working_days × 8.0 (full-time standard) | Cases 2, 3 |
| `accumulated_balance` | **Injected by BalanceRule runtime** (not built by FactBuilder) | Case 3 |

### Key design rules

1. **FactBuilder only builds facts** — it never evaluates the AST.
2. **Params come from policy assignment** (Rules Engine) — FactBuilder doesn't know about them.
3. **`accumulated_balance` is injected** by the BalanceEvaluator runtime (bucket-based ledger), not queried from DB each time.
4. **Active contract resolution**: pick the contract whose `[start_date, end_date]` overlaps the period, preferring most recent.
5. **Calendar integration**: `working_days` per period comes from the company's Calendar (accounting for public holidays).
6. **`requires` array** in the AST program tells the runtime which specific facts to build, avoiding unnecessary DB queries.
