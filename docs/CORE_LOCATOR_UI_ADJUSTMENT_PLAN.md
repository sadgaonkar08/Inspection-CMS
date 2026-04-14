# Core Locator UI Adjustment Plan

## Objective
Align the core locator experience with the updated mockups and workflow decisions:

- Report form becomes a latest-generation preview surface (no seed picker).
- Seed history remains visible in the project-directory asphalt-lot flow.
- Lock mode changes from four explicit buttons to two independent toggles (Mat, Joint).
- Add Lane becomes button-first with a blank editable row before save.
- Regeneration must still preserve locked core locations in the newest generation.

## Confirmed Product Decisions
1. The report form Overview should show the newest complete generation for the selected lot.
2. Seed history should not be selectable in the report form.
3. Seed history must remain visible in the asphalt-lot flow in project directory.
4. Sublot lock UI should be two toggles: Mat and Joint.
5. Mat/Joint counts in sublot management are generation-only inputs, defaulting to 1 and 1.
6. Add Lane should insert a blank row; inspector fills length/width and saves.

## Existing Behavior We Are Preserving
1. Locked core types are copied from prior generation to new generation (already implemented in controller/service flow).
2. Core generation records remain lot-scoped and timestamped.
3. Export flows (CSV/XLSX) continue to use generation records.
4. Existing enum lock states remain backend source of truth:
   - none
   - mat_only
   - joint_only
   - all

## Scope
### In Scope
1. Report form UI and controller behavior updates.
2. Asphalt-lot page seed-history visibility improvements.
3. Optional seed-history summary in generation detail page (upper-right summary area).
4. Lock-mode UI mapping updates in report form and lot page for consistency.
5. Add Lane interaction change to unsaved editable row flow.

### Out of Scope
1. Database schema changes for per-sublot persistent generation defaults.
2. Generator algorithm changes beyond existing lock carry-forward behavior.
3. Major redesign of generation detail diagram rendering.

## File-Level Change Plan
1. [app/views/reports/_form.html.erb](app/views/reports/_form.html.erb)
   - Remove visible seed/history selector in Overview.
   - Keep overview table as latest-generation output surface.
   - Keep tab flow and Manage in Project entrypoint.

2. [app/javascript/controllers/core_generation_selector_controller.js](app/javascript/controllers/core_generation_selector_controller.js)
   - Replace multi-generation selection logic with newest-generation resolution logic.
   - Update sublot card lock controls to Mat/Joint toggle behavior mapped to enum states.
   - Add generation-only Mat/Joint defaults in Add Sublot area (default 1/1).
   - Implement Add Lane as unsaved editable row, POST only on Save.
   - Keep Preview, Export CSV, and lot lock summary actions aligned with newest generation.

3. [app/views/asphalt_lots/show.html.erb](app/views/asphalt_lots/show.html.erb)
   - Add Core Generation History section near View Last Generation controls.
   - Show seed, created timestamp, location count, and actions (View, CSV/XLSX as applicable).
   - Keep this as required historical browsing surface.

4. [app/controllers/asphalt_lots_controller.rb](app/controllers/asphalt_lots_controller.rb)
   - Ensure show action loads ordered generation history efficiently.
   - Reuse existing JSON/history payload shape where practical.

5. [app/views/core_generations/show.html.erb](app/views/core_generations/show.html.erb) (optional enhancement)
   - Use unused upper-right area for compact recent generation links/seed history.
   - Keep diagram area uncluttered.

6. [app/controllers/core_generations_controller.rb](app/controllers/core_generations_controller.rb)
   - Allow per-sublot generate action to accept generation-only Mat/Joint defaults from UI if needed.
   - Preserve existing locked-location carry-forward logic.

7. [app/controllers/asphalt_lanes_controller.rb](app/controllers/asphalt_lanes_controller.rb)
   - No validation relaxation required if unsaved-row-first strategy is used.
   - Validate that create is only called with concrete length/width values.

## Technical Design Notes
### Latest-Generation-Only Overview
1. On lot selection, fetch generation history.
2. Select generation[0] (newest by created_at desc) as current display generation.
3. Render preview table from that generation only.
4. Store only current generation id in hidden report fields for new/edited reports under this model.

### Lock Toggle Mapping
Use deterministic mapping from two booleans to enum:

- Mat=false, Joint=false -> none
- Mat=true, Joint=false -> mat_only
- Mat=false, Joint=true -> joint_only
- Mat=true, Joint=true -> all

### Add Lane Interaction Model
1. User clicks Add Lane.
2. UI inserts a local unsaved row with blank length and width fields.
3. Save validates non-empty positive values client-side.
4. On pass, send POST create request.
5. Refresh lot panel and show success/failure status.

## Risks and Mitigations
1. Risk: breaking existing multi-generation report links.
   - Mitigation: for existing reports, preserve previously linked data in read path; only new edits follow latest-only write path unless migration strategy is chosen.

2. Risk: stale UI lock state after toggle.
   - Mitigation: refresh management payload after each lock update; avoid optimistic-only state transitions.

3. Risk: lane creation confusion with blank row.
   - Mitigation: add clear row state labels (unsaved) and inline validation messages.

4. Risk: duplicated history UI across pages causing drift.
   - Mitigation: define required source of truth as asphalt-lot page; keep generation-detail summary optional and compact.

## Delivery Sequence
1. Slice 1: Report form latest-generation-only overview and seed selector removal.
2. Slice 2: Sublot lock toggles and generation-only Mat/Joint inputs.
3. Slice 3: Add Lane unsaved-row workflow.
4. Slice 4: Asphalt-lot seed history section near View Last Generation.
5. Slice 5: Optional generation-detail upper-right summary panel.
6. Slice 6: Regression and cleanup.

## Verification Checklist
1. Select lot in report form -> overview shows newest complete generation only.
2. Lock sublot 1 Mat, regenerate full lot -> locked Mat location persists in newest overview output with other newly generated locations.
3. Add Sublot defaults show Mat=1 and Joint=1 and are used by generation flow.
4. Mat/Joint toggle states map correctly to backend enum values.
5. Add Lane creates blank editable row; invalid saves blocked; valid saves persist.
6. Asphalt-lot page shows visible generation history near View Last Generation controls.
7. Generation detail page optional upper-right panel renders cleanly if implemented.
8. Export CSV/XLSX and diagram pages continue functioning.

## Definition of Done
1. Report form no longer exposes seed selection.
2. Overview reliably displays latest complete generation.
3. Seed history is clearly visible in asphalt-lot project-directory flow.
4. Lock toggles and Add Lane behavior match mockups and accepted UX.
5. No regression in generation, locking, export, or diagram functionality.
