# Context Library — Detailed Implementation Guide

**Status:** Not started. This document provides complete instructions for building the context library referenced in Steps 2 and 7 of the AI Prompt Overhaul Plan.

---

## What the Context Library Is

A curated collection of text snippets stored in the `context_snippets` table that the AI retrieves at generation time to improve commentary quality. Each snippet is tagged by spec code, activity type, and keywords so the retriever can match relevant snippets to the report being generated.

There are three categories of snippet:

| Category | Purpose | Source | Status |
|----------|---------|--------|--------|
| `faa_spec` | Exact spec language the AI can reference when describing compliant or non-compliant work | `docs/Final_Checklist_Spec_Table (1).md` | Ready to build |
| `writing_example` | Real inspector commentary samples that demonstrate the target voice and detail level | `docs/CommentaryContext.txt` + approved reports | Partially ready (CommentaryContext.txt exists; additional approved samples needed) |
| `style_rule` | Short directives about language, tone, and what to avoid | Derived from prompt engineering feedback | Ready to build |

---

## How It Fits Into the Pipeline

The context library plugs into **Pass 2 (commentary writing)** of the two-pass pipeline in `azure_generator.rb`.

**Current flow:**
1. Pass 1 (outline) runs → produces structured bullet points
2. Pass 2 (writing) receives: outline + inspector notes + weather → produces commentary

**With context library:**
1. Pass 1 (outline) runs → produces structured bullet points
2. **Retriever** reads the report payload, identifies in-scope spec codes (from bid items + spec checklists), and pulls matching snippets from `context_snippets`
3. Pass 2 (writing) receives: outline + inspector notes + weather + **relevant context snippets** → produces commentary

The retriever replaces the dead `FaaRag::Retriever` code currently in `azure_generator.rb` (lines 196-223). The existing `retrieve_faa_standards_context` method already has the right interface — it just needs to point at `context_snippets` instead of the nonexistent `FaaStandardsChunk`.

---

## Database Table (Already Exists)

The `context_snippets` table is already in `db/schema.rb`:

```
context_snippets
├── id
├── category        (integer, enum — not null)
├── spec_code       (string — e.g., "P-401", "D-701")
├── spec_section    (string — e.g., "401-4.1", "701-3.3")
├── activity        (string — e.g., "paving", "compaction", "tack_coat", "drainage")
├── title           (string — not null, short description for admin/debugging)
├── content         (text — not null, the actual snippet text)
├── tags            (string[], GIN-indexed — keyword tags for retrieval)
├── token_count     (integer — approximate token count of content, for budget management)
├── active          (boolean, default true — allows deactivating without deleting)
├── position        (integer — ordering within a category/spec_code group)
├── timestamps
```

No migration needed. The table, indexes, and columns are all in place.

---

## Model: `ContextSnippet`

**File to create:** `app/models/context_snippet.rb`

```ruby
class ContextSnippet < ApplicationRecord
  enum category: { faa_spec: 0, writing_example: 1, style_rule: 2 }

  validates :category, :title, :content, presence: true
  validates :spec_code, presence: true, if: -> { faa_spec? || writing_example? }

  scope :active, -> { where(active: true) }
  scope :for_spec_codes, ->(codes) { where(spec_code: codes) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :tagged, ->(tag) { where("? = ANY(tags)", tag) }
  scope :ordered, -> { order(:spec_code, :position) }
end
```

---

## Retriever: `ContextLibrary::Retriever`

**File to create:** `app/services/context_library/retriever.rb`

This replaces the dead `FaaRag::Retriever` reference. The interface is simple: given a report payload, return a formatted string of relevant snippets that fits within a token budget.

```ruby
module ContextLibrary
  class Retriever
    DEFAULT_TOKEN_BUDGET = 2000  # Max tokens of context to inject into Pass 2
    
    def initialize(token_budget: DEFAULT_TOKEN_BUDGET)
      @token_budget = token_budget
    end

    # Main entry point — called from azure_generator.rb
    # Returns a formatted string ready to inject into the prompt, or '' if nothing found.
    def retrieve_for_report(payload)
      spec_codes = extract_spec_codes(payload)
      return '' if spec_codes.empty?

      snippets = ContextSnippet.active
                               .for_spec_codes(spec_codes)
                               .ordered
                               .to_a

      return '' if snippets.empty?

      # Budget-aware selection: pick snippets until we hit the token limit
      selected = select_within_budget(snippets)
      format_snippets(selected)
    end

    private

    def extract_spec_codes(payload)
      codes = Set.new

      # From bid items
      (payload[:bid_items] || []).each do |item|
        codes << item[:code] if item[:code].present?
      end

      # From spec checklists
      (payload[:spec_checklists] || []).each do |checklist|
        code = checklist[:code] || checklist[:spec_code]
        codes << code if code.present?
      end

      codes.to_a
    end

    def select_within_budget(snippets)
      selected = []
      remaining = @token_budget

      # Priority: faa_spec first (grounding), then writing_example (voice),
      # then style_rule (directives)
      priority_order = %w[faa_spec writing_example style_rule]

      priority_order.each do |cat|
        snippets.select { |s| s.category == cat }.each do |snippet|
          cost = snippet.token_count.positive? ? snippet.token_count : estimate_tokens(snippet.content)
          break if remaining - cost < 0
          selected << snippet
          remaining -= cost
        end
      end

      selected
    end

    def estimate_tokens(text)
      (text.length / 4.0).ceil  # Rough approximation
    end

    def format_snippets(snippets)
      return '' if snippets.empty?

      grouped = snippets.group_by(&:category)
      sections = []

      if grouped['faa_spec']&.any?
        lines = grouped['faa_spec'].map { |s| "- [#{s.spec_code} §#{s.spec_section}] #{s.content}" }
        sections << "FAA Specification References:\n#{lines.join("\n")}"
      end

      if grouped['writing_example']&.any?
        lines = grouped['writing_example'].map { |s| "- [#{s.spec_code}] #{s.content}" }
        sections << "Writing Examples:\n#{lines.join("\n")}"
      end

      if grouped['style_rule']&.any?
        lines = grouped['style_rule'].map { |s| "- #{s.content}" }
        sections << "Style Rules:\n#{lines.join("\n")}"
      end

      sections.join("\n\n")
    end
  end
end
```

---

## Integration Into `azure_generator.rb`

Replace the current dead `retrieve_faa_standards_context` method with:

```ruby
def retrieve_faa_standards_context(outline, payload)
  retriever = ContextLibrary::Retriever.new
  context = retriever.retrieve_for_report(payload)
  
  Rails.logger.info("[ReportAi::AzureGenerator] Retrieved context library: #{context.length} chars")
  context
rescue StandardError => e
  Rails.logger.warn("[ReportAi::AzureGenerator] Context retrieval failed: #{e.message}")
  ''
end
```

And add `{{context_snippets}}` to the Pass 2 system prompt (appended after the hardcoded reference examples). Once snippet quality is validated, the hardcoded examples can be retired.

---

## Phase 1: FAA Spec Excerpt Snippets

### Source

`docs/Final_Checklist_Spec_Table (1).md` — ~185 rows covering 12 spec items:
D-701, D-751, P-101, P-151, P-152, P-209, P-219, P-401, P-403, P-603, P-610, P-621

### What each snippet looks like

One `context_snippet` record per checklist question row:

| Field | Value | Example |
|-------|-------|---------|
| `category` | `faa_spec` | |
| `spec_code` | Spec item from table | `P-603` |
| `spec_section` | Section from table | `603-3.3` |
| `activity` | Derived from spec code (see mapping below) | `tack_coat` |
| `title` | Checklist question (truncated) | `Surface cleaned before tack application` |
| `content` | The spec quote from the table | `"Immediately before applying the emulsified asphalt tack coat..."` |
| `tags` | Array of keywords derived from spec code + question | `["P-603", "tack", "surface", "cleaning"]` |
| `token_count` | Calculated from content length | `45` |
| `active` | `true` | |
| `position` | Row order within spec code | `1` |

### Spec code → activity mapping

Use this mapping to populate the `activity` field. This enables filtering by activity type when multiple spec codes are in scope.

```ruby
SPEC_ACTIVITY_MAP = {
  "D-701" => "drainage",
  "D-751" => "drainage_structures",
  "P-101" => "pavement_removal",
  "P-151" => "clearing_grubbing",
  "P-152" => "earthwork",
  "P-209" => "aggregate_base",
  "P-219" => "recycled_base",
  "P-401" => "asphalt_paving",
  "P-403" => "asphalt_paving",
  "P-603" => "tack_coat",
  "P-610" => "concrete",
  "P-621" => "pavement_grooving"
}
```

### Tag generation rules

Tags are the primary retrieval mechanism. Generate them by:

1. **Spec code** — always include (e.g., `"P-603"`)
2. **Activity** — from the mapping above (e.g., `"tack_coat"`)
3. **Key nouns from the question** — extract 2-4 significant terms:
   - "Is the surface cleaned of all dust, dirt, loose material..." → `["surface", "cleaning", "dust"]`
   - "Is pipe installation starting at the lowest point with bell ends facing upgrade?" → `["pipe", "installation", "bell_end", "grade"]`
4. **Non-compliance indicator** — if the spec quote contains tolerance language ("shall not exceed", "minimum of", "not less than"), add `"tolerance"` tag

Keep tags lowercase, use underscores for multi-word terms, and keep the total under 8 tags per snippet.

### Rows to exclude or flag

- Rows where Spec Section is `NOT FOUND IN SPECIFICATION` or `N/A` — create the snippet but set `active: false` and add a `"needs_review"` tag
- Duplicate rows (same spec_code + substantially identical question) — keep the one with the more specific spec quote, skip the other
- Rows where the spec quote is very short (<20 chars) or appears truncated — flag with `"needs_review"` tag

### Seed script

**File to create:** `db/seeds/context_snippets.rb` (or add a section to `db/seeds.rb`)

The script should:
1. Parse `docs/Final_Checklist_Spec_Table (1).md` row by row
2. For each row, create a `ContextSnippet` with the mapping above
3. Calculate `token_count` as `(content.length / 4.0).ceil`
4. Use `find_or_create_by` on `(category, spec_code, spec_section, title)` to be idempotent
5. Print a summary: total created, skipped (duplicates), flagged (needs_review)

---

## Phase 2: Writing Example Snippets

### Source

Primary: `docs/CommentaryContext.txt` — contains ~15 real inspector commentary entries covering:
- Storm drain / RCP installation (D-701)
- Concrete placement (P-610)
- Asphalt paving with detailed temps, roller specs, and QA (P-401)
- Tack coat operations (P-603)
- Milling / pavement removal (P-101)
- Marking blackout (P-620)
- FOD walks and cleanup
- Conduit removal
- Trench inspection and deficiency documentation

Secondary (future): Additional approved commentary entries from inspectors, tagged and curated.

### What each snippet looks like

Writing examples are **paragraph-length excerpts** pulled from real commentary, not full reports. Each excerpt demonstrates a specific activity type.

| Field | Value | Example |
|-------|-------|---------|
| `category` | `writing_example` | |
| `spec_code` | Primary spec item the excerpt covers | `P-401` |
| `spec_section` | Leave blank for writing examples | |
| `activity` | Activity type | `asphalt_paving` |
| `title` | Short description | `P-401 paving with temp readings and roller detail` |
| `content` | The excerpt paragraph | `"Asphalt was delivered in 27 belly dump trucks, deposited in windrows..."` |
| `tags` | Activity + key terms | `["P-401", "asphalt_paving", "temperature", "compaction", "roller"]` |
| `token_count` | Calculated | `120` |

### How to extract from CommentaryContext.txt

The file contains full commentary entries separated by `---` dividers. Each entry may cover multiple activities. The extraction process:

1. Split the file on `---` dividers to get individual entries
2. For each entry, identify which spec items it covers (look for P-xxx and D-xxx references, or infer from activity descriptions)
3. Break multi-activity entries into **focused excerpts** — one per activity type. For example, a paving entry that covers tack coat, mat placement, and compaction becomes three snippets
4. Keep excerpts to 1-3 paragraphs maximum. The retriever has a token budget — shorter, focused excerpts are more useful than long narratives
5. Preserve the inspector's actual voice — do not edit or clean up the language. That's the whole point

### Excerpt boundaries

Split on natural activity transitions. Look for these signals:
- New activity starting: "Prior to paving...", "After completing...", "The crew then...", "Following placement..."
- Spec item change: mention of a different P-item
- Time jump: new time reference indicating a different phase of work

### What still blocks full Phase 2

- Additional approved commentary entries beyond CommentaryContext.txt need to be collected from inspectors
- Each new entry needs to be tagged by spec code and activity type
- Target: at least 3-5 examples per major spec code (P-401, P-603, P-610, P-152, D-701)
- CommentaryContext.txt gets us good coverage for P-401, P-603, P-610, and D-701 but is thin on P-152, P-209, and P-621

---

## Phase 3: Style Rule Snippets

Short, directive snippets that encode the prompt engineering feedback we've already dialed in. These reinforce the system prompt with retrievable rules matched to specific activities.

### Examples

| spec_code | activity | content |
|-----------|----------|---------|
| `P-401` | `asphalt_paving` | `When describing compaction, state that the mat was compacted to the required density per the mix design and specification. Do not use vague terms like "good" or "satisfactory."` |
| `P-401` | `asphalt_paving` | `Report actual temperature readings when available (e.g., "ranging from 330 to 356 degrees Fahrenheit"). Do not round or generalize.` |
| `P-603` | `tack_coat` | `Describe surface preparation before tack application — what equipment was used (sweeper, vacuum truck, leaf blowers) and that the surface was cleaned of dust and debris.` |
| `P-610` | `concrete` | `For concrete placement, describe the delivery method (truck chute, pump, buggy), consolidation method (internal vibrator), and finish type (trowel, broom, float).` |
| `D-701` | `drainage` | `For pipe installation, include pipe size, type (RCP, HDPE), direction of bell ends, bedding material and depth, and any dewatering operations.` |
| `*` | `*` | `Use "nuclear density gauge" — never "nuke gauge" or "nuke." Translate all inspector shorthand to formal technical language.` |

Style rules with `spec_code: "*"` are global — the retriever should always include them regardless of which spec codes are in scope. Keep the total count of style rules low (10-15 max) to avoid overwhelming the prompt.

---

## Token Budget Management

The retriever operates within a token budget (default 2,000 tokens) to prevent context snippets from bloating the Pass 2 prompt. Priority order:

1. **Style rules** (global `*` rules first) — these are small and high-impact
2. **FAA spec excerpts** matching in-scope spec codes — grounding for citations
3. **Writing examples** matching in-scope spec codes — voice guidance

If the budget runs out mid-category, stop. It's better to have complete coverage of high-priority snippets than partial coverage of everything.

### Monitoring

Log the number of snippets retrieved and total token count in `azure_generator.rb`. If outputs are frequently hitting the budget ceiling, consider:
- Shortening verbose spec quotes to the most relevant sentence
- Increasing the budget (but watch total prompt size)
- Adding more specific tags so fewer irrelevant snippets are retrieved

---

## Rollout Plan

| Phase | What to seed | Snippet count (est.) | Can ship? |
|-------|-------------|---------------------|-----------|
| 1a | FAA spec excerpts from Final Checklist Table | ~185 | Yes — source data ready |
| 1b | Style rules from prompt engineering feedback | ~10-15 | Yes — rules already defined in system prompt |
| 2a | Writing examples from CommentaryContext.txt | ~20-30 | Yes — file exists, needs extraction |
| 2b | Additional writing examples from approved reports | ~30-50 | Blocked — need inspector-approved samples |

**Ship order:** 1a + 1b together (retriever + spec excerpts + style rules), then 2a (writing examples from existing file), then 2b (ongoing curation).

After 1a + 1b are seeded and the retriever is wired in, the hardcoded reference examples in the Pass 2 system prompt can be retired — the writing examples from Phase 2a will replace them dynamically.

---

## Relationship to spec_reference (Overhaul Plan Step 2)

The context library and `spec_reference` enrichment are **complementary but independent**:

- **`spec_reference`** goes on individual checklist question objects in the database. It provides deterministic, per-question citations (e.g., "P-603 §4.3.2(a)") that appear in the Pass 1 outline. This is the primary citation mechanism.

- **Context library FAA snippets** provide the actual spec language behind those citations. When Pass 2 sees a non-compliance flag with a spec reference, it can also see the relevant spec quote in the context snippets, which helps it write accurate descriptions of what the spec requires.

You can ship either one without the other. But they work best together: `spec_reference` tells the AI *which* spec section was violated, and the context library tells it *what that section says*.

---

## Files to Create

| File | Purpose |
|------|---------|
| `app/models/context_snippet.rb` | Model with enum, validations, scopes |
| `app/services/context_library/retriever.rb` | Tag-based retrieval with token budgeting |
| `db/seeds/context_snippets.rb` | Seed script parsing Final Checklist Table |
| `lib/tasks/context_library.rake` | Rake tasks: `context_library:seed`, `context_library:stats`, `context_library:reset` |

## Files to Modify

| File | Change |
|------|--------|
| `app/services/report_ai/azure_generator.rb` | Replace dead `FaaRag::Retriever` with `ContextLibrary::Retriever` |
| `app/services/report_ai/prompt_templates.rb` | Add `{{context_snippets}}` placeholder to Pass 2 system or user prompt |

## Dead Code to Clean Up

| File | What to remove |
|------|---------------|
| `azure_generator.rb` | References to `FaaStandardsChunk` (line 199) |
| `Gemfile` | `pgvector` gem (re-add later if vector search is needed) |
