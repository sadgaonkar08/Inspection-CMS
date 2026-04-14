# Lab Test PDF Import & Tracking — Feature Plan

**Status:** Planning complete — ready for implementation.

---

## Overview

A per-project tool to upload lab test report PDFs, extract structured test result rows, review uncertain extractions, and display finalized results in a filterable, copy-friendly table with CSV export.

**Spec types covered:** P-152, P-401, P-403, P-610

**Sample PDFs available:**
- `docs/P-403_03.16.2026_LOT-TS(SC)_AME_FAIL_CORES.pdf` — P-403 core density, AME lab
- `docs/P-610_03.12.2026_92262_DAY28_RMA_PASS.pdf` — P-610 28-day cylinder break, RMA lab
- Representative P-152 sample set (assumed available for parser implementation and validation)

---

## Design Decisions

| Question | Decision |
|---|---|
| Where in the app? | Per-project page, alongside bid items and asphalt lots |
| Display format | On-screen HTML table; easy to manually copy into Excel |
| Excel export | CSV download for now; investigate `.xlsx` output as a separate task |
| Lot/bid item linkage | Deferred — standalone records for now, add optional linkage later |
| Review step | Auto-save if confidence ≥ 0.80; route to manual review if below threshold |
| PDF format | Mostly text-based; occasional scanned images handled gracefully |
| Extraction strategy | Deterministic parsers first; AI fallback only for fields the parser missed |

---

## Field Schemas

### P-401 / P-403 — Asphalt In-Place Cores / Density
*(P-401 and P-403 use near-identical report formats)*

| Field | Description |
|---|---|
| `lab_name` | Testing laboratory name |
| `report_number` | Lab report number |
| `test_date` | Date of testing |
| `lot_number` | Asphalt lot |
| `sublot_number` | Sublot within the lot |
| `location` | Station or location description |
| `core_id` | Core sample identifier |
| `core_thickness_in` | Measured core thickness (inches) |
| `bulk_specific_gravity` | Gmb |
| `max_specific_gravity` | Gmm (Rice value) |
| `air_voids_pct` | Va (%) |
| `compaction_pct` | % Gmm achieved |
| `required_compaction_pct` | Spec minimum (%) |
| `result` | pass / fail |

### P-610 — Concrete Cylinder Breaks

| Field | Description |
|---|---|
| `lab_name` | Testing laboratory name |
| `report_number` | Lab report number |
| `test_date` | Date of cylinder break |
| `pour_date` | Date concrete was placed |
| `break_age_days` | Break age: 7, 14, or 28 days |
| `set_id` | Sample / set identifier |
| `mix_design_id` | Concrete mix design reference |
| `location` | Pour location description |
| `break_strength_psi` | Measured compressive strength (psi) |
| `required_strength_psi` | Spec minimum strength (psi) |
| `result` | pass / fail |

### P-152 — Embankment Compaction

| Field | Description |
|---|---|
| `lab_name` | Testing laboratory name |
| `report_number` | Lab report number |
| `test_date` | Date of testing |
| `location` | Station or location description |
| `test_number` | Sequential test number |
| `proctor_max_dry_density_pcf` | Lab proctor maximum dry density (pcf) |
| `proctor_optimum_moisture_pct` | Lab proctor optimum moisture (%) |
| `field_dry_density_pcf` | In-place measured dry density (pcf) |
| `field_moisture_pct` | In-place measured moisture (%) |
| `compaction_pct` | % compaction achieved |
| `required_compaction_pct` | Spec minimum (%) |
| `result` | pass / fail |

---

## Architecture

### Phase 1 — Database

Two new tables following the existing `ImportedReport` staging pattern.

#### `lab_test_imports` (staging)

| Column | Type | Notes |
|---|---|---|
| `project_id` | bigint FK | NOT NULL |
| `user_id` | bigint FK | NOT NULL — uploader |
| `spec_code` | string | `"P-401"`, `"P-403"`, `"P-610"`, `"P-152"` |
| `lab_name` | string | Detected from PDF header |
| `status` | string | `pending` → `needs_review` / `saved` / `rejected` |
| `raw_text` | text | Full text extracted from PDF |
| `parsed_data` | jsonb | Array of extracted row hashes |
| `confidence_score` | float | 0.0–1.0 |
| `extraction_errors` | text | Error messages if extraction failed |
| `source_pdf` | ActiveStorage | Attached PDF file |

#### `lab_test_results` (finalized records)

| Column | Type | Notes |
|---|---|---|
| `project_id` | bigint FK | NOT NULL |
| `lab_test_import_id` | bigint FK | Optional — traceability back to import |
| `spec_code` | string | NOT NULL |
| `lab_name` | string | |
| `report_number` | string | |
| `test_date` | date | |
| `location` | string | |
| `data` | jsonb | All spec-specific fields (schema varies per spec_code) |
| `result` | string | `pass` / `fail` / `pending` |
| `notes` | text | Manual notes added during review |
| `created_by_id` | bigint FK | User who finalized/approved |

**Files:**
- `db/migrate/..._create_lab_test_imports.rb`
- `db/migrate/..._create_lab_test_results.rb`

---

### Phase 2 — Python Extraction Script

**Strategy: deterministic-first, AI fallback only for missing fields.**

```
python/
  extract_lab_report.py       ← dispatcher / orchestrator
  parsers/
    ame_p401_p403.py          ← AME lab, P-401 / P-403 format
    rma_p610.py               ← RMA lab, P-610 format
      p152_base.py              ← P-152 embankment compaction parser
    ...                       ← one module per lab+spec, added as new PDFs arrive
```

#### `extract_lab_report.py` — execution steps

1. Use `pdfplumber` to extract full text and tables from all pages
2. Detect lab name by matching known header strings in first-page text
3. Dispatch to the matching parser in `parsers/`
4. Parser returns `{ rows, fields_found, fields_missing }` for each data row
5. **If `fields_missing` is empty** → return immediately; **no AI call made**
6. **If any fields are missing (fallback):**
   - Call Azure OpenAI with only the raw text + a targeted prompt listing the specific missing fields (e.g. `"Please extract the following fields: [core_thickness_in, bulk_specific_gravity]"`)
   - Merge AI-returned values back into the rows
   - Tag each field value with `_source: "parser"` or `_source: "ai"` so the review UI can highlight AI-filled cells
7. Re-score: `confidence = total_fields_found / total_fields_expected` across all rows
8. Return JSON:

```json
{
  "spec_code": "P-403",
  "lab_name": "AME",
  "parser_used": "ame_p401_p403",
  "raw_text": "...",
  "rows": [
    {
      "core_id": { "value": "C-1", "_source": "parser" },
      "bulk_specific_gravity": { "value": 2.341, "_source": "parser" },
      "air_voids_pct": { "value": 4.2, "_source": "ai" }
    }
  ],
  "confidence": 0.91,
  "errors": [],
  "scanned": false
}
```

#### Edge cases

| Scenario | Behavior |
|---|---|
| Unknown lab (no parser match) | AI receives full raw text + full spec schema as last resort; `errors: ["unknown_lab"]` |
| Scanned image (no extractable text) | Skip AI entirely; `errors: ["no_text_scanned"]`; route to `needs_review` with clear message |
| Parser found but all fields missing | Treated same as unknown lab — full AI fallback |

#### Parser module contract

Each `parsers/*.py` module must expose:

```python
EXPECTED_FIELDS = ["core_id", "core_thickness_in", ...]  # defines the schema

def parse(pages: list, tables: list) -> dict:
    # returns { "rows": [...], "fields_missing": [...] }
```

New parsers drop in here with no changes to `extract_lab_report.py`.

#### `python/requirements.txt` additions
```
pdfplumber>=0.10.0
openai>=1.0.0        # only imported at runtime when AI fallback is triggered
```

**New files:**
- `python/extract_lab_report.py`
- `python/parsers/ame_p401_p403.py`
- `python/parsers/rma_p610.py`
- `python/parsers/p152_base.py`

**Modified:**
- `python/requirements.txt`

---

### Phase 3 — Ruby Bridge Service

`app/services/python_pdf_extractor.rb` — mirrors the existing `PythonDocxImporter` pattern exactly:

```ruby
PythonPdfExtractor.extract(pdf_path: "/tmp/foo.pdf", spec_code: "P-403")
# => { "rows" => [...], "confidence" => 0.91, ... }
```

Calls `python/extract_lab_report.py` via `Open3.capture3`, parses JSON stdout, raises on non-zero exit.

**Files:**
- `app/services/python_pdf_extractor.rb`

---

### Phase 4 — Background Job

`app/jobs/lab_test_extraction_job.rb`

1. Receive `lab_test_import_id`
2. Download PDF from ActiveStorage to a temp file
3. Call `PythonPdfExtractor.extract(pdf_path:, spec_code:)`
4. Update `lab_test_import` with `parsed_data`, `confidence_score`, `raw_text`, `lab_name`
5. **If confidence ≥ 0.80** → auto-create `LabTestResult` rows, mark import `saved`
6. **If confidence < 0.80** → mark import `needs_review`; user reviews on the show page
7. **On exception** → mark import `rejected`, store message in `extraction_errors`

The 0.80 threshold is a starting point — tune after observing real imports.

**Files:**
- `app/jobs/lab_test_extraction_job.rb`

---

### Phase 5 — Models

#### `LabTestImport`
```ruby
belongs_to :project
belongs_to :user
has_one_attached :source_pdf
has_many :lab_test_results
enum status: { pending: "pending", needs_review: "needs_review", saved: "saved", rejected: "rejected" }
```

#### `LabTestResult`
```ruby
belongs_to :project
belongs_to :lab_test_import, optional: true
belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"
enum result: { pass: "pass", fail: "fail", pending_result: "pending" }
scope :by_spec_code, ->(code) { where(spec_code: code) }
scope :by_result,    ->(r)    { where(result: r) }
scope :by_date_range, ->(from, to) { where(test_date: from..to) }
```

#### `Project` additions
```ruby
has_many :lab_test_imports, dependent: :destroy
has_many :lab_test_results, dependent: :destroy
```

**Files:**
- `app/models/lab_test_import.rb`
- `app/models/lab_test_result.rb`
- `app/models/project.rb` *(modified)*

---

### Phase 6 — Controllers & Routes

#### Routes (nested under `resources :projects`)

```ruby
resources :lab_test_imports, only: [:new, :create, :show, :destroy] do
  member do
    patch :approve
    patch :reject
  end
end

resources :lab_test_results, only: [:index, :edit, :update, :destroy] do
  collection do
    get :export_csv
  end
end
```

#### `LabTestImportsController`

| Action | Description |
|---|---|
| `new` | Upload form — file picker + spec_code select |
| `create` | Save attached PDF, enqueue `LabTestExtractionJob`, redirect to `show` |
| `show` | Status page — pending spinner / needs_review table / saved summary |
| `approve` | Persist `parsed_data` rows to `lab_test_results`, mark import `saved` |
| `reject` | Mark import `rejected` |

#### `LabTestResultsController`

| Action | Description |
|---|---|
| `index` | Filterable table — filter by spec_code, result, date range |
| `edit` | Edit an individual result row |
| `update` | Save edited row |
| `destroy` | Delete a result row |
| `export_csv` | Download CSV with columns matching the displayed table |

**Files:**
- `app/controllers/lab_test_imports_controller.rb`
- `app/controllers/lab_test_results_controller.rb`
- `config/routes.rb` *(modified)*

---

### Phase 7 — Views

#### Upload form — `lab_test_imports/new`

- File input (PDF only)
- `spec_code` dropdown: P-401, P-403, P-610, P-152
- Submit triggers background job; page transitions to `show` for status polling

#### Status / review page — `lab_test_imports/show`

| Import status | UI shown |
|---|---|
| `pending` | Spinner + Turbo auto-refresh polling |
| `needs_review` | Editable table of extracted rows; confidence score indicator; AI-filled cells highlighted; Approve / Reject buttons |
| `saved` | Summary card (lab, spec, row count, date) + link to results table |
| `rejected` | Error message + option to re-upload |

AI-sourced cell values should be visually distinct (e.g. light yellow background) in the review table so reviewers know what to scrutinize.

#### Results table — `lab_test_results/index`

- Filter bar: spec_code tabs or dropdown, pass/fail toggle, date range picker
- P-401 and P-403 share the same column partial
- Spec-specific column partials:
  - `_columns_p401_p403.html.erb`
  - `_columns_p610.html.erb`
  - `_columns_p152.html.erb`
- Result badge: pass = green, fail = red, pending = gray
- Each row: Edit and Delete actions
- CSV Download button
- "Upload New Report" button → `new` import page

**Files:**
- `app/views/lab_test_imports/new.html.erb`
- `app/views/lab_test_imports/show.html.erb`
- `app/views/lab_test_results/index.html.erb`
- `app/views/lab_test_results/edit.html.erb`
- `app/views/lab_test_results/_columns_p401_p403.html.erb`
- `app/views/lab_test_results/_columns_p610.html.erb`
- `app/views/lab_test_results/_columns_p152.html.erb`

---

### Phase 8 — Frontend (Stimulus)

`app/javascript/controllers/lab_test_import_controller.js`

- Polls `GET /projects/:id/lab_test_imports/:id.json` on an interval
- When status changes from `pending`, replaces the status UI via Turbo or innerHTML swap
- Mirrors the existing `report_export_controller.js` pattern

**Files:**
- `app/javascript/controllers/lab_test_import_controller.js`

---

## Complete File List

### New files

```
db/migrate/..._create_lab_test_imports.rb
db/migrate/..._create_lab_test_results.rb
app/models/lab_test_import.rb
app/models/lab_test_result.rb
app/jobs/lab_test_extraction_job.rb
app/services/python_pdf_extractor.rb
app/controllers/lab_test_imports_controller.rb
app/controllers/lab_test_results_controller.rb
app/views/lab_test_imports/new.html.erb
app/views/lab_test_imports/show.html.erb
app/views/lab_test_results/index.html.erb
app/views/lab_test_results/edit.html.erb
app/views/lab_test_results/_columns_p401_p403.html.erb
app/views/lab_test_results/_columns_p610.html.erb
app/views/lab_test_results/_columns_p152.html.erb
app/javascript/controllers/lab_test_import_controller.js
python/extract_lab_report.py
python/parsers/ame_p401_p403.py
python/parsers/rma_p610.py
python/parsers/p152_base.py
```

### Modified files

```
config/routes.rb               — add nested lab_test_imports and lab_test_results
python/requirements.txt        — add pdfplumber, openai
app/models/project.rb          — add has_many :lab_test_imports, :lab_test_results
```

### Reference files (patterns to follow)

```
app/services/python_docx_importer.rb                    — Ruby→Python bridge pattern
app/models/imported_report.rb                           — staging model pattern
app/services/report_ai/azure_generator.rb               — Azure OpenAI call pattern
app/javascript/controllers/report_export_controller.js  — async polling Stimulus pattern
app/services/core_location_xlsx_exporter.rb             — CSV/XLSX export pattern
```

---

## Verification Checklist

- [ ] Upload `P-403_03.16.2026_LOT-TS(SC)_AME_FAIL_CORES.pdf` → AME parser fires, all core rows extracted, result = fail, confidence ≥ 0.80, auto-saved
- [ ] Upload `P-610_03.12.2026_92262_DAY28_RMA_PASS.pdf` → RMA parser fires, cylinder break fields extracted, result = pass, auto-saved
- [ ] Upload representative P-152 embankment compaction PDF → P-152 parser fires, compaction fields extracted, confidence scored correctly, auto-save/review routing behaves per threshold
- [ ] Force low-confidence result → import routes to `needs_review`, review table shows correct rows, AI-sourced cells highlighted, Approve saves to `lab_test_results`
- [ ] Submit a scanned/image PDF → `no_text_scanned` error, routes to `needs_review` with clear message, no AI call attempted
- [ ] Submit PDF from unknown lab → AI fallback fires, result reviewed before saving
- [ ] Results table: filter by each spec code, filter by pass/fail, filter by date range
- [ ] CSV export: correct column headers per spec, all rows present, opens cleanly in Excel
- [ ] Edit a result row → saved correctly
- [ ] Delete a result row → removed from table
- [ ] Reject an import → marked rejected, re-upload option shown

---

## Further Considerations

### Performance Guardrails (pre-implementation)

To keep extraction responsive and avoid unnecessary database and API load, implement these defaults in the first pass.

#### 1) Job throughput and queue isolation
- Put lab extraction on a dedicated queue (`lab_extraction`) separate from UI-critical jobs
- Start with conservative concurrency (e.g. 2-4 workers for extraction queue) and tune after observing CPU usage
- Add `started_at`, `finished_at`, and `retry_count` tracking so stuck/pending imports can be surfaced and requeued safely

#### 2) Polling efficiency
- Expose a compact JSON status payload for polling (`status`, `confidence_score`, `error_count`, `updated_at`)
- Poll with backoff (e.g. 2s → 3s → 5s max), and stop polling immediately when status enters terminal states
- Prefer status-only responses over full-page HTML rerenders during `pending`

#### 3) Database read/write balance
- Add indexes that match actual filters on `lab_test_results`: `(project_id, spec_code)`, `(project_id, result)`, `(project_id, test_date)`
- Add status/time indexes on `lab_test_imports`: `(project_id, status, created_at)`
- Avoid over-indexing `jsonb` fields until query patterns prove a need

#### 4) Idempotent writes under retries
- Use deterministic row fingerprints (e.g. hash of normalized row payload + report metadata) to prevent duplicate result rows
- Insert finalized rows with upsert semantics where possible to reduce retry overhead and duplicate cleanup work
- Wrap import finalization in a single DB transaction so status/result rows stay consistent

#### 5) AI and parsing cost controls
- Call AI only when parser-missing fields exist (already planned), and send only targeted missing-field prompts
- Enforce schema validation before saving AI-merged values to avoid downstream correction churn
- Add hard limits for extracted text size sent to AI to prevent latency spikes on unusually large PDFs

#### 6) Payload size management
- Store full `raw_text` only when needed for review/debug; otherwise store a capped excerpt + reference metadata
- Keep `parsed_data` normalized and compact (avoid duplicating unchanged metadata in every row)
- For CSV export, stream generation for large result sets to avoid high memory use in web workers

### Confidence threshold tuning
0.80 is a starting estimate. After the first 10–20 real imports, adjust based on how often extractions route to `needs_review` unnecessarily vs. how often auto-saved results contain errors.

### Adding new lab parsers
When a new lab's PDF format is encountered:
1. Run `pdfplumber` against a sample and inspect the raw text structure
2. Create `python/parsers/<lab>_<spec>.py` with `EXPECTED_FIELDS` and `parse()`
3. Add the lab name detection string to `extract_lab_report.py`'s dispatch table
4. No other files need to change

### Extraction strategy recap
Deterministic parser runs first (fast, free, no API call). AI is called **only** for specific fields the parser couldn't extract — a targeted prompt, not a full re-extraction. In the fully-working-parser case, AI is never invoked. Cost stays near zero.

### Lot linkage (future)
`lab_test_results` has no foreign key to `AsphaltLot` or `BidItem` yet. A follow-up migration can add optional `asphalt_lot_id` / `bid_item_id` columns so results appear on lot management pages and cross-reference from daily reports.

### XLSX export (future)
Investigate why `caxlsx` output is not working correctly as a separate task. A proper `.xlsx` download would allow better column formatting and formula support for tracking spreadsheets.

### P-152 parser
Plan and implementation assumptions should treat P-152 as fully supported with deterministic parsing first, then targeted AI fallback for truly missing fields, matching P-401/P-403/P-610 behavior.
