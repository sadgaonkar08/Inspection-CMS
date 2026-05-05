# PWL Calculation Feature — Implementation Plan

Reference: [C-110 PWL Calculations.pdf](C-110%20PWL%20Calculations.pdf) (FAA AC 150/5370-10H, Item C-110)

## 1. Background — what the spec actually requires

PWL (Percent Within Limits) is computed **per lot, per parameter**, using all sublot test values in that lot:

1. `X` = sample mean of sublot values
2. `Sn` = sample std dev (using `n-1` denominator — Bessel's correction)
3. Compute Quality Index:
   - Single-sided lower limit: `QL = (X - L) / Sn`
   - Single-sided upper limit: `QU = (U - X) / Sn`
   - Double-sided: both
4. Look up Q in **Table 1** (rows = PWL 1–99, cols = n=3…10) to get `PL` and/or `PU`
   - Rule: "if Q falls between rows, use the next higher PWL" → algorithm = find smallest table-Q ≥ our Q
5. Final:
   - Single-sided: `PWL = PL` (or `PU`)
   - Double-sided: `PWL = (PL + PU) − 100`

For P-401 the expected parameters are **Mat Density** (single-sided, e.g. L=96.3) and **Air Voids** (double-sided, e.g. L=2.0/U=5.0). The spec also references ASTM E178 outlier screening before PWL.

## 2. Scope decisions

| # | Decision | Proposed | Alternative |
|---|----------|----------|-------------|
| A | Which P-401 parameters? | **Air Voids** (double-sided), **Mat Density** (single-sided) | Add VMA, VFA, asphalt content, gradation later |
| B | Where do mat density values come from? | **P-403 cores parser** — already extracts `compaction_pct` per core (mat + joint) and is wired up in `extract_lab_report.py` | Extend P-401 parser to read cores section if present |
| C | Spec limit source | **Air voids:** already extracted from PDF (`air_voids_min_pct`/`max_pct`). **Mat density:** also extracted from P-403 PDF (`required_compaction_pct`, e.g. mat ≥ 94%, joint ≥ 92%) | Add a project-level config table for limits not in any PDF |
| D | n bounds | Support **n=3…10** via Table 1 (covers ~all real lots). For n<3, mark "insufficient data". For n>10, mark "requires EB 57 extended table" until transcribed | Implement EB 57 in v1 |
| E | Outliers (ASTM E178) | **Phase 2** — flag-only, don't auto-exclude | Skip entirely / build in v1 |
| F | Pay factor / deductions | **Out of scope** for v1 — PWL only | Bundle pay factor in v1 |

## 3. Data model

### New table: `pwl_calculations`
One row per `(asphalt_lot, parameter)`. Stores both inputs and outputs so the calc is auditable.

```
asphalt_lot_id       :bigint, index
parameter            :string  ("air_voids", "mat_density", "joint_density", …)
n                    :integer
sample_values        :jsonb   (frozen snapshot of inputs used)
mean                 :decimal
std_dev              :decimal
lower_limit          :decimal, nullable
upper_limit          :decimal, nullable
q_lower              :decimal, nullable
q_upper              :decimal, nullable
p_lower              :integer, nullable
p_upper              :integer, nullable
pwl_percentage       :integer, nullable
status               :string  ("ok", "insufficient_n", "n_too_large", "missing_limits", "stale")
calculated_at        :datetime
unique index on (asphalt_lot_id, parameter)
```

**Why a dedicated table** (not columns on `asphalt_lots`): PWL is per-parameter, will grow over time, and needs the per-step values surfaced for inspectors who will absolutely audit the math.

### Optional: `spec_tolerances` (only if needed for limits not in any PDF)
```
project_id    :bigint
spec_code     :string  ("P-401")
parameter     :string  ("mat_density")
lower_limit   :decimal, nullable
upper_limit   :decimal, nullable
unique on (project_id, spec_code, parameter)
```
PDF-extracted limits would still take precedence; this is a fallback for parameters where limits aren't in a report.

### No changes needed to
`lab_test_results`, `asphalt_lots`, `lab_test_imports` — already have everything needed:
- Sublot values in `data` JSONB (`air_voids_avg` for P-401, `compaction_pct` for P-403)
- Lot association via `asphalt_lot_id`
- Limits already extracted (`air_voids_min_pct`/`max_pct`, `required_compaction_pct`)

## 4. Calculation engine

New service object: `app/services/pwl_calculator.rb`

```
PwlCalculator.new(asphalt_lot, parameter:).call → PwlCalculation
```

Internals:
- `Pwl::QTable` — the n=3…10 lookup table from page 5 of the spec, encoded as a frozen constant. One method: `lookup(q, n) → percent_within_limits` using "smallest table-Q ≥ our Q" rule.
- `Pwl::Statistics` — `mean`, `sample_std_dev` (n-1 denom). Pure functions, easy to unit test.
- `PwlCalculator` — orchestrates: pulls sublot values from lot's lab results, validates n and limits, calls statistics + Q-table, persists `PwlCalculation`.

**Q-table encoding** — transcribe Table 1 from PDF page 5 directly into a Ruby constant. Two halves (positive + negative Q) form one table indexed by `[pwl_percent][n]`. ~99 × 8 = 792 values; tedious but one-time. Unit-test against the spec's worked example (`QL=1.4348, n=4 → PWL=98`) and the air-voids example (`PWL=90`) to verify transcription.

**Source values for each parameter:**
- `air_voids` → `lab_test_result.data["air_voids_avg"]` from each sublot's P-401 result in the lot
- `mat_density` → `lab_test_result.data["compaction_pct"]` from P-403 results where `core_type="mat"`
- `joint_density` → P-403 results where `core_type="joint"` (single-sided, lower-only)

## 5. Trigger points (when to (re)calculate)

Recompute is cheap — just run it whenever inputs may have changed:

1. **After `LabTestExtractionJob` saves results** — enqueue `PwlRecalculationJob` for the affected `asphalt_lot_id`(s).
2. **After manual edits** to `LabTestResult` or limits — model callback enqueues the same job.
3. **Manual recompute button** on the lot page (UI escape hatch).

`PwlRecalculationJob` runs `PwlCalculator` for each supported parameter on the lot, idempotently upserting the `pwl_calculations` row.

## 6. UI

**Lot show page** (`app/views/asphalt_lots/show.html.erb`) — new "PWL Analysis" section. One card per parameter. Layout (top → bottom):

1. **Category label** ("Air Voids") above the hero, small caps / muted.
2. **Hero metric** — `PWL: 74%` centered, large display font, color-coded to PWL band:
   - ≥ 90 → success green
   - 75–89 → warning amber
   - < 75 → danger red
   These match typical FAA pay-factor breakpoints; intent is at-a-glance triage, not a hard contractual signal.
3. **"Last calculated …"** timestamp directly below the hero, muted.
4. **Inputs grid** — four equal cells in a horizontal row: `n`, `X` (mean), `Sₙ` (std dev), `Sample values`. Sample values cell is wider on desktop. Each cell: a small label on top, a larger value below.
5. **Calculation breakdown** — two columns side by side:
   - Left: **Lower Limit** card with `L = …`, `QL = (X − L) / Sₙ = …`, `PL = …`
   - Right: **Upper Limit** card with `U = …`, `QU = (U − X) / Sₙ = …`, `PU = …`
   For single-sided parameters, only one column renders, full-width.
6. **Final formula** — centered below the breakdown, e.g. `PWL = (PL + PU) − 100 = (100 + 74) − 100 = 74`.
7. **Legend** — bottom strip, two-column key:
   - `n` Number of sublots
   - `X` Sample Mean
   - `Sₙ` Sample Standard Deviation
   - `L / U` Lower / Upper Specification Limit
   - `QL / QU` Lower / Upper Quality Index
   - `PL / PU` Percent Within Lower / Upper Limit

**Visual style** — uses the existing `form-card` / CSS-variable design system (no Tailwind dependency). Hero number uses `--font-accent` (Space Grotesk) for visual weight; data cells and breakdown cards have subtle borders + tinted backgrounds; ample whitespace separates sections.

**Status states** — `insufficient_n`, `n_too_large`, `missing_limits` replace the hero + breakdown with a single muted message and a status badge in the corner. Empty state ("no calculations yet") shown when `@pwl_calculations.empty?`.

**Lab results table** (`_columns_p401_hma.html.erb`) — leave untouched (PWL is a lot-level stat, not a result-level one).

**Reports** — add PWL to the daily/lot inspection report PDF templates as a second pass.

## 7. Edge cases & validation

- `n < 3` → status `insufficient_n`, no PWL
- `n > 10` → status `n_too_large` until EB 57 table transcribed
- `Sn = 0` (all values identical) → Q is infinite; if X is within limits, PWL = 100; else 0
- Q outside table range → clamp: Q above row 99 → PWL=100; Q below row 1 → PWL=0
- Missing L or U → if a parameter is double-sided in spec but only one limit configured, fail with `missing_limits`
- Outliers — Phase 2; for v1 just compute on whatever is there

## 8. Testing strategy

- **Unit tests for `Pwl::Statistics`** — known-mean / known-stddev fixtures
- **Unit tests for `Pwl::QTable`** — every row from the spec's example walkthrough, plus boundary cases (rounding rule)
- **Integration test for `PwlCalculator`** — both worked examples from the spec PDF (Mat Density → 98, Air Voids → 90) using fabricated lab results. These are gold standards.
- **Job test** — uploading a P-401 PDF triggers PWL recompute end-to-end

## 9. Suggested phasing

| Phase | Deliverable |
|-------|------------|
| **1a** | Q-table encoded + statistics + calculator service, with spec-example tests passing. No DB, no UI yet. |
| **1b** | `pwl_calculations` table + recompute job + auto-trigger from extraction job. Air voids only. |
| **1c** | UI on lot show page. Ship to users for air voids. |
| **2** | Mat density + joint density (P-403 source) |
| **3** | ASTM E178 outlier flagging |
| **4** | EB 57 extended Q-table (n>10), PDF report integration, pay factor |

## 10. Open questions

1. **Lot definition** — confirm `asphalt_lot_id` on `lab_test_result` is always the right grouping for PWL (vs. needing date/shift filtering).
2. Real reference data — a real P-401 PDF + the contractor's submitted PWL number to validate end-to-end before shipping.
3. Display granularity — show all four parameters (air voids, mat density, joint density, asphalt content if added later) in one combined PWL panel, or split per spec code?

## 11. Notes on existing extractors

- **P-401 HMA mix (air voids)**: extracted by [python/parsers/ame_p401_hma.py](../python/parsers/ame_p401_hma.py) — `air_voids_avg`, `air_voids_min_pct`, `air_voids_max_pct` per sublot. ✅
- **Cores (mat/joint density)**: extracted by [python/parsers/ame_p403_cores.py](../python/parsers/ame_p403_cores.py) — `compaction_pct`, `core_type` ("mat"/"joint"), `required_compaction_pct` per core. ✅ Verified against `docs/P-403_04.15.2026_LOT-TS2(PL)_AME_PASS_CORES.pdf` — 6 rows, 0 errors. The same parser now serves both P-403 and P-401 cores reports — `extract_lab_report.py` dispatches by content via `ame_common.is_cores_report` before falling back to the HMA parser for P-401.
- No new extractor work needed for v1.

### Downstream UI follow-up (not yet done)

`app/views/lab_test_results/index.html.erb` groups results by `spec_code` only and picks a column partial via `spec_partial_key`. A P-401 cores report would land in the P-401 group but render with the HMA partial (`_columns_p401_hma.html.erb`) — fields won't match. Two options when a real P-401 cores PDF arrives:

1. Add a `result_kind` column to `lab_test_results` (set from `parser_used` at import time), group by `(spec_code, result_kind)`, render `_columns_p401_cores.html.erb` (a thin reuse of `_columns_p403_cores.html.erb`).
2. Group by `(spec_code, parser_used)` in the view and route via parser name.

Option 1 is more invasive but cleaner for filtering/exports.
