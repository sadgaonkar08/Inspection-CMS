# Pre-Rollout Issue Triage — Ranked by Impact

> **Status as of May 2026:** 8 of 10 issues fully shipped, 1 partially shipped (server-side only), 1 open. See ✅/⚠️ markers below.

## TIER 1 — Active Bugs Causing Data Loss or Corruption

### #4 — Only one attachment saved at a time `CRITICAL` ✅ FIXED

Root cause is **not** a cache issue — `nginx.conf` has no `client_max_body_size` directive, which defaults to **1MB**. Phone photos are 3–8 MB each, so submitting a form with even one uncompressed photo can silently fail with a 413 error. The Rails nested attributes system already supports multiple attachments.

**Fix**: add `client_max_body_size 50M;` to `nginx.conf`. The user's "Fix A" (auto-save per photo) is a UX enhancement, not the root fix. "Fix B" (expand cache) is a red herring.

**Files**: `nginx.conf`

**Resolution:** `client_max_body_size 50M;` added to `nginx.conf`.

---

### #2 — Weather breaks for overnight shifts `CRITICAL` ✅ FIXED

The midpoint calculation in `app/javascript/controllers/report_form_controller.js` (lines 232–348) does `Math.round((startHour + endHour) / 2)`. A 22:00–06:00 shift yields hour **14** (2 PM) — completely wrong. The API call also only fetches data for `start_date`, missing next-day hours entirely.

**Fix**: detect overnight (`endHour < startHour`), add 24 for midpoint calculation, fetch two days of hourly data from Open-Meteo.

**Files**: `app/javascript/controllers/report_form_controller.js`

**Resolution:** Overnight detection added — adjusts midpoint math when `endHour < startHour` and fetches two calendar days from Open-Meteo.

---

### #1 — Weather doesn't update when shift time changes `HIGH` ✅ FIXED

`autoFetchWeather()` runs once on page load via `connect()`. There are **no event listeners** on the `shift_start`/`shift_end` inputs. Changing shift times does nothing.

**Fix**: add `change` event listeners on both inputs to re-trigger the weather fetch with the new times.

**Files**: `app/javascript/controllers/report_form_controller.js`, `app/views/reports/_form.html.erb`

**Resolution:** `setupShiftTimeWeatherListeners()` adds change listeners on both inputs with 800ms debounce, calling `autoFetchWeather()`.

---

## TIER 2 — Usability Blockers for Field Inspectors

### #3 — Photo compression before upload `HIGH` ⚠️ SERVER-SIDE SHIPPED, CLIENT-SIDE OPTIONAL

Server-side compression is fully implemented. `app/models/report_attachment.rb:11` enqueues `ReportAttachmentCompressionJob` on create/update when `image_needs_compression?` returns true (image content type, size > `ImageCompressor::MAX_BYTES` = 3 MB). `app/services/image_compressor.rb` uses `ImageProcessing::MiniMagick` to resize to 4096px max, strip EXIF, convert non-JPEG (incl. HEIC/HEIF) to JPEG, and binary-search quality between 75–92 to land under 3 MB. Combined with the 50 MB nginx limit (#4), uploads are no longer broken.

The remaining gap is **client-side** compression. With nginx at 50 MB nothing is rejected at the edge, but cellular uploads of raw 6–8 MB iPhone photos still take 10–20s each. This is a quality-of-life optimization, not a correctness fix.

**Recommended approach if pursued**: skip the `browser-image-compression` npm package (this app uses importmap-rails — adding npm deps requires vendoring a UMD build). Use native `Canvas` + `toBlob('image/jpeg', 0.82)` in `report_form_controller.js`, capped at ~1600px, with silent fall-through to the original on failure (Canvas can't decode HEIC on Android Chrome — the server-side job catches that case).

**Files**: `app/javascript/controllers/report_form_controller.js` (only — server side is done)

**Resolution (server-side):** `ReportAttachment#after_commit :enqueue_image_compression` + `ImageCompressor` service handle resize, EXIF strip, HEIC→JPEG conversion, and quality binary search asynchronously via Sidekiq.

---

### #6 — Add delete report button `HIGH` ✅ FIXED

The `destroy` action exists in the controller (`reports_controller.rb` lines 190–193) and routes are registered, but **no UI button** is exposed. Inspectors with erroneous reports have no recourse.

**Fix**: add a `button_to` with `method: :delete` and a Turbo confirmation dialog to `app/views/reports/show.html.erb`, gated to creator/admin roles. Consider soft-delete (`discarded_at` column) if audit trail matters.

**Files**: `app/views/reports/show.html.erb`, possibly `app/models/report.rb`

**Resolution:** `button_to "Delete Report"` with Turbo confirmation dialog added to `app/views/reports/show.html.erb`.

---

### #5 — User emails need names `MEDIUM` ✅ FIXED

The User model has **no name fields** — only `email`. `report.rb` `inspector_name` returns `user.email`, and `inspector_initials` is hardcoded. Both appear in exported Word documents.

**Fix**: migration to add `first_name`/`last_name` to `users` table, update `inspector_name`/`inspector_initials` methods, and ideally auto-populate names from Azure AD claims during SSO login.

**Files**: New migration, `app/models/user.rb`, `app/models/report.rb` (lines 241–248), SSO callback controller

**Resolution:** Migration added `first_name`/`last_name` to `users`. `User#full_name` and `User#initials` methods use real names. SSO callback auto-populates names from Azure AD claims.

---

## TIER 3 — Data Seeding & Configuration

### #7 — Missing FAA specs and checklists `MEDIUM` ✅ FIXED

~13 spec items are seeded but P-219 and others are missing. The schema fully supports this — `spec_items` has `checklist_questions` (JSONB) and `bid_items` link to specs per project.

**Fix**: data-only migration or seed update. Requires the project specification documents to enumerate exactly which items and checklist questions to add.

**Files**: `db/seeds.rb` or a new migration file

**Resolution:** Data migrations added for P-219, P-603, P-610, D-701, D-751, P-152, P-209, P-621. P-625 (typo) removed.

---

### #10 — Default to correct project `LOW` ⚠️ SCOPED DOWN — SEED RENAME ONLY

The original report described a hardcoded `Project.find_by(name: ...)` lookup in the controller. That bug does not exist: `app/controllers/reports_controller.rb:80–83` falls back to `Project.order(created_at: :desc).first`, which is safe and never returns the wrong project by name. The remaining issue is purely cosmetic — the seeded project name in `db/seeds.rb:72` is "Runway 1R Rehabilitation" rather than the desired "Runway 1R-19L Rehabilitation & TWY W".

**Fix**: update the project name in `db/seeds.rb:72`. Note that `find_or_create_by!` will not rename existing dev/staging rows — those need a one-off `UPDATE projects SET name = 'Runway 1R-19L Rehabilitation & TWY W' WHERE name = 'Runway 1R Rehabilitation'` or a data migration. View placeholder text referencing "Runway 1R" (`_form.html.erb:19`, `_overview_tab.html.erb:77`) is unaffected and can stay.

**Files**: `db/seeds.rb` (line 72), plus a data migration for existing rows.

---

### #9 — SoV category for bid items `LOW` ⚠️ OPEN — NEEDS VOCABULARY DECISION

`sov_category` column exists on `bid_items` (`db/schema.rb:124`, indexed at line 128) and **is** actively read by the UI: it appears as a column in `app/views/projects/_bid_items_tab.html.erb:26` and `app/views/bid_items/index.html.erb:41`, and powers the "Group by SoV Category" option in the data view (`app/views/reports/data_view.html.erb:71`, backed by `app/controllers/reports_controller.rb:491–551`). Today every value is blank, so the grouping falls through to "Uncategorized."

**Fix**: pick a category vocabulary, then update `db/seeds.rb` bid-item creation blocks to set `sov_category` per item. Suggested grouping based on FAA spec divisions:
- **Earthwork**: P-152, P-209, P-210
- **Base Course**: P-304, P-306
- **Paving**: P-401, P-403, P-501, P-502
- **Marking**: P-620, P-621
- **Drainage**: P-610

Existing dev/staging rows will need a backfill — seeds use `find_or_create_by!` so re-seeding alone won't update them.

**Files**: `db/seeds.rb`, plus a data migration for existing rows.

---

## TIER 4 — UX Polish

### #8 — Remind users about 6-photo limit `LOW` ✅ FIXED

`app/views/reports/_form.html.erb:742–750` shows a static reminder ("Up to 6 photos will be included in Word exports. Additional attachments are saved but won't appear in the report document.") plus a conditional `alert-warning` banner that fires when `attachment_count > 6`. The 6-photo cap is enforced server-side at export time via `.limit(PHOTO_SLOT_COUNT)` in `app/services/python_docx_exporter.rb:228`.

**Files**: `app/views/reports/_form.html.erb`

**Resolution:** Static reminder + dynamic over-limit warning shipped. Note: `PHOTO_SLOT_COUNT = 6` is duplicated across three files (`python/export_report.py:53`, `app/services/python_docx_exporter.rb:6`, `app/services/report_ai/payload_builder.rb:6`) — DRYing across Ruby + Python is non-trivial and tracked separately if ever needed.

---

## Further Considerations

1. **#4 and #3 are coupled** — fixing nginx alone lets large files through but doesn't solve slow mobile uploads. Both should ship together.
2. **#6 soft vs. hard delete** — needs stakeholder input. Hard delete is simpler; soft delete (via `discarded_at` column) preserves an audit trail.
3. **#5 Azure AD integration** — if SSO is active, names can be auto-populated from OIDC claims in the OmniAuth callback, avoiding manual data entry entirely.

---

## Verification Checklist

- [x] **#4**: Upload 3+ phone photos (3 MB each) simultaneously → all persist after save
- [x] **#2**: Create report with shift 22:00–06:00 → weather slots show correct hours (22:00, 02:00, 06:00)
- [x] **#1**: Change shift_start from 07:00 to 10:00 → weather auto-refetches for new times
- [x] **#3 (server-side)**: Upload a 6 MB photo → Sidekiq job replaces it with a < 3 MB JPEG within seconds
- [ ] **#3 (client-side, optional)**: Upload from phone → file leaves the device < 1 MB
- [x] **#6**: Delete button visible on report show page → confirm dialog → report removed → redirect to index
- [x] **#5**: User with name set → export shows "John Smith" not "jsmith@company.com"
- [x] **#7**: New spec items visible in checklist dropdowns when creating a report
- [ ] **#10**: Seeded project renamed to "Runway 1R-19L Rehabilitation & TWY W" + existing rows backfilled
- [ ] **#9**: SoV categories populated and visible on bid items
- [x] **#8**: Warning text visible in attachments section of report form (and over-limit banner fires at 7+)
