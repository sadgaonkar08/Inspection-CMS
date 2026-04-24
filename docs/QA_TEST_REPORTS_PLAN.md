# Lab Test PDF Import & Tracking — Feature Plan

**Status:** Planning — asphalt (P-401, P-403) only. P-152 and P-610 deferred.

---

## Overview

A per-project tool to upload asphalt lab test PDFs, extract structured test data via deterministic Python parsers, surface anything partially extracted for manual review, and display finalized results in a filterable, copy-friendly table with CSV export.

**In scope (this pass):**
- **P-401 HMA** — loose mix sampled at plant, Superpave gyratory results (Gmb / Gmm / air voids)
- **P-403 cores** — in-place drilled cores, density/compaction results

**Out of scope (deferred):**
- P-152 embankment compaction
- P-610 concrete cylinder breaks
- Azure OpenAI / AI fallback extraction
- Linking results to `AsphaltLot` / `CoreLocation` records

**Sample PDFs available:**
- `docs/P-401_04.15.2026_LOT-TS2(P)_AME_PASS_HMA.pdf` — AME lab, P-401 HMA gyratory, 3 sublots (TS2-SL1/2/3)
- `docs/P-403_03.16.2026_LOT-TS(SC)_AME_FAIL_CORES.pdf` — AME lab, P-403 cores, 6 cores (3 mat + 3 joint)

Both samples are text-based (clean `pdfplumber` output, no OCR needed).

---

## Design Decisions

| Question | Decision |
|---|---|
| Where in the app? | Per-project page, alongside bid items and asphalt lots |
| Display format | On-screen HTML table; easy to manually copy into Excel |
| Excel export | CSV download for now; `.xlsx` a separate follow-up |
| Lot/bid item linkage | Deferred — standalone records for now |
| Extraction strategy | Deterministic parsers only; no AI this pass |
| Review routing | Parser fully succeeded → `saved`; parser hit any error or missing required field → `needs_review` |
| PDF format | Text-based only; scanned images rejected with a clear error |

---

## Important: P-401 and P-403 are NOT the same report format

Although both sample PDFs come from the same lab (AME) with an identical letterhead, they test completely different things and produce different record shapes. They need separate parsers and separate display columns.

### P-401 HMA — per-sublot gyratory results

One row per sublot. Each sublot has replicate measurements with averages.

| Field | Example | Notes |
|---|---|---|
| `sublot_number` | `TS2-SL1` | String, parsed from header line |
| `test_date` | `2026-04-15` | From `Test Date: 4/15/26 @ 74T` |
| `tonnage_point_tons` | `74` | From `@ 74T` on test date line |
| `time_in_oven_hrs` | `2` | From `(Time in Oven: 2 hrs)` |
| `gyrations` | `75` | From intro paragraph, constant per report |
| `gmb_samples` | `[2.396, 2.394, 2.397]` | 3 replicates, ASTM D2726 |
| `gmb_avg` | `2.396` | |
| `gmm_samples` | `[2.463, 2.469]` | 2 replicates, ASTM D2041 |
| `gmm_avg` | `2.466` | |
| `air_voids_samples` | `[2.83, 2.90, 2.80]` | 3 replicates, ASTM D3203 |
| `air_voids_avg` | `2.84` | |
| `air_voids_min_pct` | `2.5` | From `Project Requirement: Air Voids 2.5% to 4.5%` |
| `air_voids_max_pct` | `4.5` | |
| `result` | `pass` / `fail` | Computed: `air_voids_min ≤ air_voids_avg ≤ air_voids_max` |

### P-403 cores — per-core in-place density

One row per core. Report has cores grouped by type (mat vs joint), each group with its own threshold.

| Field | Example | Notes |
|---|---|---|
| `sublot_number` | `TS/SL1` | String from `Lot/Sublot` header row |
| `core_id` | `M1`, `J1` | |
| `core_type` | `mat` / `joint` | Drives `required_compaction_pct` |
| `thickness_as_received_in` | `4.70` | |
| `thickness_trimmed_in` | `4.20` | |
| `gmb` | `2.434` | Bulk specific gravity (ASTM D2726 for mat, D1188 for joint) |
| `gmm` | `2.483` | Theoretical max specific gravity |
| `compaction_pct` | `98.0` | |
| `astm_standard` | `D2726` / `D1188` | Differs by core type in the AME format |
| `required_compaction_pct` | `94` for mat, `92` for joint | From `Project Requirements: Mat. ≥ 94% ; Joint ≥ 92%` |
| `result` | `pass` / `fail` | Computed: `compaction_pct ≥ required_compaction_pct` |

### Shared report header (both specs)

Extracted by a common helper, stored on the import record:

| Field | Example |
|---|---|
| `lab_name` | `AME` (Applied Materials & Engineering) |
| `report_date` | `2026-03-23` (date on the letter) |
| `project_number` | `1260185T` |
| `project_subject` | `Runway 1R-19L and Taxiway W Rehabilitation` |
| `plant` | `Granite - Pleasanton Plant` / `Granite - Santa Clara Plant` |
| `mix_number` | `15345` / `15347` |

---

## Architecture

### Phase 1 — Python extraction (start here)

**Deterministic parsers only.** No AI. Each parser reads the full text via `pdfplumber.extract_text()` and uses regex/string matching against the known AME format.

```
python/
  extract_lab_report.py           ← dispatcher
  test_extract.py                 ← CLI harness: prints JSON for a given PDF
  parsers/
    __init__.py
    ame_common.py                 ← shared header parser + numeric helpers
    ame_p401_hma.py               ← P-401 HMA gyratory
    ame_p403_cores.py             ← P-403 cores in-place density
```

#### Dispatcher contract

```
python/extract_lab_report.py --pdf <path> --spec P-401|P-403
```

1. Open PDF with `pdfplumber`, extract full text from all pages
2. If no text at all → emit `{"error": "no_text_scanned"}` and exit 2
3. Detect lab from header (`"Applied Materials & Engineering"` → `AME`)
4. Dispatch to the matching parser by `(spec, lab)` — currently only AME supported for both
5. Parser returns rows + report header; dispatcher wraps and emits JSON to stdout

#### Parser module contract

Each `parsers/<lab>_<spec>.py` exposes:

```python
EXPECTED_FIELDS = [...]                # schema keys, for downstream validation

def parse(text: str) -> dict:
    # returns:
    # {
    #   "header": { "lab_name": "AME", "report_date": "2026-03-23", ... },
    #   "rows":   [ { ...row_fields... }, ... ],
    #   "errors": [ "missing_field:air_voids_avg@TS2-SL2", ... ]
    # }
```

#### Dispatcher output JSON

```json
{
  "spec_code": "P-401",
  "parser_used": "ame_p401_hma",
  "header": {
    "lab_name": "AME",
    "report_date": "2026-04-16",
    "project_number": "1260185T",
    "plant": "Granite - Pleasanton Plant",
    "mix_number": "15347"
  },
  "rows": [
    {
      "sublot_number": "TS2-SL1",
      "test_date": "2026-04-15",
      "tonnage_point_tons": 74,
      "time_in_oven_hrs": 2,
      "gyrations": 75,
      "gmb_samples": [2.396, 2.394, 2.397],
      "gmb_avg": 2.396,
      "gmm_samples": [2.463, 2.469],
      "gmm_avg": 2.466,
      "air_voids_samples": [2.83, 2.90, 2.80],
      "air_voids_avg": 2.84,
      "air_voids_min_pct": 2.5,
      "air_voids_max_pct": 4.5,
      "result": "pass"
    }
  ],
  "errors": [],
  "row_count": 3
}
```

#### Edge cases

| Scenario | Behavior |
|---|---|
| Scanned PDF (no extractable text) | Exit 2, `errors: ["no_text_scanned"]` — Rails routes to `needs_review` |
| Unknown lab header | Exit 3, `errors: ["unknown_lab"]` |
| Parser found report but missed a required field | Row included, `errors` lists each miss; Rails routes to `needs_review` |
| Parser crash (unexpected exception) | Exit 1, stderr carries traceback; Rails marks `rejected` |

#### `python/requirements.txt` additions

```
pdfplumber>=0.11.0
```

(No `openai` — no AI fallback this pass.)

---

### Phase 2 — Database

Two new tables, mirroring the existing `ImportedReport` staging pattern.

#### `lab_test_imports` (staging)

| Column | Type | Notes |
|---|---|---|
| `project_id` | bigint FK | NOT NULL |
| `user_id` | bigint FK | NOT NULL — uploader |
| `spec_code` | string | `"P-401"` or `"P-403"` |
| `lab_name` | string | From extracted header |
| `status` | string | `pending` → `saved` / `needs_review` / `rejected` |
| `raw_text` | text | Full text extracted from PDF (capped — see below) |
| `report_header` | jsonb | Lab-level header fields |
| `parsed_data` | jsonb | Array of extracted row hashes |
| `extraction_errors` | jsonb | Array of error strings / codes |
| `row_count` | integer | For quick display without parsing jsonb |
| `source_pdf` | ActiveStorage | Attached PDF file |

Indexes: `(project_id, status, created_at)`, `(project_id, spec_code)`.

#### `lab_test_results` (finalized records)

| Column | Type | Notes |
|---|---|---|
| `project_id` | bigint FK | NOT NULL |
| `lab_test_import_id` | bigint FK | NOT NULL — traceability back to import |
| `spec_code` | string | NOT NULL — drives which column partial / schema to use |
| `lab_name` | string | |
| `report_date` | date | From import header |
| `test_date` | date | Row-specific (P-401 has per-sublot dates; P-403 uses report date) |
| `sublot_number` | string | Indexed for filtering |
| `data` | jsonb | All spec-specific fields — schema varies by `spec_code` |
| `result` | string | `pass` / `fail` |
| `notes` | text | Manual notes added during review |
| `created_by_id` | bigint FK | User who finalized |

Indexes: `(project_id, spec_code)`, `(project_id, result)`, `(project_id, test_date)`.

**Files:**
- `db/migrate/..._create_lab_test_imports.rb`
- `db/migrate/..._create_lab_test_results.rb`

---

### Phase 3 — Ruby bridge service

`app/services/python_pdf_extractor.rb` — mirrors `PythonDocxImporter`.

```ruby
PythonPdfExtractor.extract(pdf_path: "/tmp/foo.pdf", spec_code: "P-401")
# => { "spec_code" => "P-401", "header" => {...}, "rows" => [...], "errors" => [...] }
```

Calls `python/extract_lab_report.py` via `Open3.capture3`, parses JSON stdout, raises on unexpected exit codes (treats exit 2/3 as structured errors, not exceptions).

---

### Phase 4 — Background job

`app/jobs/lab_test_extraction_job.rb` on a dedicated `:lab_extraction` queue.

1. Download attached PDF to a temp file
2. Call `PythonPdfExtractor.extract(pdf_path:, spec_code:)`
3. Update `lab_test_import` with `raw_text`, `report_header`, `parsed_data`, `extraction_errors`, `row_count`, `lab_name`
4. **If `errors` empty AND every expected field present on every row** → auto-create `LabTestResult` rows, mark import `saved`
5. **Otherwise** → mark import `needs_review`
6. **On exception** → mark import `rejected`, store message in `extraction_errors`

All finalization happens in a single DB transaction so partial failures leave the import in a clean state.

Use ActionCable (same pattern as `ReportExportJob`) to push status changes to the show page — no polling.

---

### Phase 5 — Models

#### `LabTestImport`
```ruby
belongs_to :project
belongs_to :user
has_one_attached :source_pdf
has_many :lab_test_results, dependent: :nullify
enum status: { pending: "pending", needs_review: "needs_review", saved: "saved", rejected: "rejected" }
```

#### `LabTestResult`
```ruby
belongs_to :project
belongs_to :lab_test_import
belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"
enum result: { pass: "pass", fail: "fail" }
scope :by_spec_code,  ->(code) { where(spec_code: code) }
scope :by_result,     ->(r)    { where(result: r) }
scope :by_date_range, ->(from, to) { where(test_date: from..to) }
```

#### `Project` additions
```ruby
has_many :lab_test_imports, dependent: :destroy
has_many :lab_test_results, dependent: :destroy
```

---

### Phase 6 — Controllers & routes

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
| `new` | Upload form — file picker + spec_code select (P-401 / P-403) |
| `create` | Validate PDF MIME + size cap, attach, enqueue `LabTestExtractionJob`, redirect to `show` |
| `show` | Status page — live-updates via ActionCable |
| `approve` | Persist `parsed_data` rows to `lab_test_results`, mark import `saved` (used when reviewer manually corrects a `needs_review` import) |
| `reject` | Mark import `rejected` |

#### `LabTestResultsController`

| Action | Description |
|---|---|
| `index` | Filterable table — filter by spec_code, result, date range |
| `edit` / `update` / `destroy` | Single-row CRUD |
| `export_csv` | CSV download with column set matching the selected spec |

---

### Phase 7 — Views

#### Upload form — `lab_test_imports/new`
- File input (accept `application/pdf` only, client + server validated)
- `spec_code` dropdown: P-401, P-403

#### Status / review page — `lab_test_imports/show`

| Import status | UI shown |
|---|---|
| `pending` | Spinner + ActionCable live status |
| `needs_review` | Editable table of extracted rows + list of missing-field errors; Approve / Reject buttons |
| `saved` | Summary card (lab, spec, sublot/core count, report date) + link to results table |
| `rejected` | Error message + option to re-upload |

#### Results table — `lab_test_results/index`

- Filter bar: spec_code tabs (P-401 / P-403), pass/fail toggle, date range picker
- **Separate column partials per spec** (they show different data):
  - `_columns_p401_hma.html.erb` — sublot, tonnage pt, Gmb avg, Gmm avg, air voids avg, min/max req, result
  - `_columns_p403_cores.html.erb` — sublot, core ID, core type, thickness (trimmed), Gmb, Gmm, compaction %, req %, result
- Result badge: pass = green, fail = red
- Each row: Edit / Delete actions
- CSV Download button
- "Upload New Report" button → `new` import page

---

### Phase 8 — Frontend (Stimulus)

`app/javascript/controllers/lab_test_import_controller.js`

- Subscribes to an ActionCable channel for the import
- On status change, swaps the status UI via Turbo Streams
- Mirrors `report_export_controller.js`

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
app/views/lab_test_results/_columns_p401_hma.html.erb
app/views/lab_test_results/_columns_p403_cores.html.erb
app/javascript/controllers/lab_test_import_controller.js
app/channels/lab_test_import_channel.rb
python/extract_lab_report.py
python/test_extract.py
python/parsers/__init__.py
python/parsers/ame_common.py
python/parsers/ame_p401_hma.py
python/parsers/ame_p403_cores.py
```

### Modified files

```
config/routes.rb               — add nested lab_test_imports and lab_test_results
python/requirements.txt        — add pdfplumber
app/models/project.rb          — add has_many :lab_test_imports, :lab_test_results
```

### Reference files (patterns to follow)

```
app/services/python_docx_importer.rb                    — Ruby→Python bridge pattern
app/models/imported_report.rb                           — staging model pattern
app/jobs/report_export_job.rb                           — job + broadcast pattern
app/javascript/controllers/report_export_controller.js  — ActionCable status UI
app/services/core_location_xlsx_exporter.rb             — CSV/XLSX export pattern
```

---

## Verification Checklist

### Python (Phase 1)
- [ ] `python/test_extract.py docs/P-401_04.15.2026_LOT-TS2(P)_AME_PASS_HMA.pdf P-401` → JSON with 3 sublot rows, all `result: pass`, no errors
- [ ] `python/test_extract.py docs/P-403_03.16.2026_LOT-TS(SC)_AME_FAIL_CORES.pdf P-403` → JSON with 6 core rows (3 mat + 3 joint); joint J1 `result: fail` (91.8% < 92%), others pass
- [ ] Non-text/scanned PDF → exit 2, `no_text_scanned` error
- [ ] Unrecognized lab header → exit 3, `unknown_lab` error

### Rails (Phases 2–8, added later)
- [ ] Upload each sample PDF → background job runs, import ends in `saved`, correct row count
- [ ] Force a malformed PDF → routes to `needs_review` with readable error list
- [ ] Results table filter by spec / result / date
- [ ] CSV export: columns match selected spec, opens cleanly in Excel
- [ ] Edit / Delete a result row
- [ ] Reject an import → marked rejected, re-upload option shown

---

## Further Considerations

### Performance Guardrails

- Dedicated `:lab_extraction` Sidekiq queue so PDF work doesn't crowd UI jobs
- Indexes on `lab_test_results (project_id, spec_code)`, `(project_id, result)`, `(project_id, test_date)`
- `lab_test_imports (project_id, status, created_at)`
- Cap stored `raw_text` size (e.g. 200KB) — we only need it for review/debug
- Stream CSV export for large result sets

### Idempotency

- Use a deterministic fingerprint on each parsed row (hash of `import_id + sublot_number + core_id`) to prevent duplicate `lab_test_results` if the job retries mid-finalization
- Wrap finalization in a single DB transaction

### Upload hardening

- Server-side MIME check (`application/pdf`) — don't trust the client
- File size cap (e.g. 10MB) on `lab_test_imports.source_pdf`
- Authorization: uploader must have access to the project (standard controller scoping)

### Adding new lab parsers later

When a non-AME lab's PDF arrives:
1. Run `pdfplumber` against a sample and inspect text structure
2. Add `python/parsers/<lab>_<spec>.py` with a `parse(text)` function
3. Add the lab detection string to `extract_lab_report.py`'s dispatch map
4. No other files change

### Future follow-ups (explicitly deferred)

- P-152 embankment compaction parser + schema
- P-610 concrete cylinder break parser + schema
- AI fallback for unknown labs or partial extractions
- Optional linkage of `LabTestResult` → `AsphaltLot` / `CoreLocation` so results appear on the lot page
- `.xlsx` export with styled columns (investigate why `caxlsx` output isn't rendering correctly)
