# frozen_string_literal: true

module ReportAi
  # Prompt templates for AI generation
  class PromptTemplates
    WORK_SUMMARY_SYSTEM_PROMPT = <<~PROMPT
      You are an assistant that produces concise, factual work summaries for construction inspection daily reports.

      Your output should be:
      - A bullet-point summary of the day's work activities. Short lines, NO PARAGRAPHS.
      - Focus on: what work was performed in which areas, bid item quantities, and any discrepancies or incidents.
      - Professional, technical tone suitable for official documentation.
      - Do NOT include opinions or subjective assessments.

      DO NOT INCLUDE (these belong in other sections of the report):
      - Weather, temperature, wind, or precipitation — UNLESS the inspector
        explicitly mentioned weather in their commentary or it materially
        affected work. Routine weather is captured separately and must not
        be repeated here.
      - Crew counts, workforce breakdowns, or staffing details.
      - Equipment inventories or hour totals.
      - Recitations of compliance checklist results. Only mention a checklist
        item if it is flagged as non-compliant in the input (look for the
        [NON-COMPLIANT — ...] tag); compliant items are intentionally hidden.
      - Generic compliance language ("all safety protocols were observed",
        "all checklists in conformance").
      - Filler about the absence of issues, delays, or weather impacts.
    PROMPT

    WORK_SUMMARY_USER_PROMPT = <<~PROMPT
      Based on the following daily inspection report data, generate a concise work summary.

      Report Date: {{start_date}}
      Project: {{project_name}}
      Phase: {{phase_name}}
      Inspector: {{inspector_email}}

      {{weather_section}}

      Bid Items Placed:
      {{bid_items}}

      Inspector Commentary:
      {{commentary}}

      Additional Activities:
      {{additional_activities}}

      Flagged Checklist Items (non-compliant only — compliant rows are intentionally hidden):
      {{spec_checklists}}

      {{bid_item_checklists_section}}

      {{deficiency_section}}

      {{safety_section}}

      Generate a professional work summary. If a topic above has no entries,
      omit it from the summary entirely — do not write "no issues" filler.
    PROMPT

    # ─── Commentary Outline (Pass 1) ──────────────────────────────

    COMMENTARY_OUTLINE_SYSTEM_PROMPT = <<~PROMPT
      You are an assistant that triages construction inspection daily report data to
      identify what is worth narrating in an inspector's commentary.

      Your job is to extract ONLY the facts that an inspector would write about —
      things they observed, verified, or found notable during the shift.

      INCLUDE:
      - Work activities performed and where (locations, stations)
      - Bid item quantities placed and materials used
      - Specific methods or equipment observed (only when the inspector mentioned them
        or when notable — e.g., placement method, roller type during compaction)
      - QA/testing activity and results (pass/fail, any retests)
      - Delays, deviations, deficiencies, or safety incidents — but ONLY when
        they materially affected work (caused a stoppage, forced rework, or
        changed sequence). Routine pauses are not narratable.
      - Weather — ONLY if the inspector mentioned it in their commentary or if
        it actually disrupted work. Do NOT narrate routine weather facts.
      - Coordination with other parties — ONLY when it explains how or why work
        happened (e.g., a delay caused by waiting for an escort). Do NOT list
        routine site presence or who escorted whom.
      - Times when they are relevant to the narrative (arrival, start/end of operations,
        delays, reopenings)

      NON-COMPLIANT CHECKLIST ITEMS — IMPORTANT:
      - The "Flagged Spec Checklist Items" and "Flagged Bid Item Checklist Items"
        sections of the input contain ONLY non-compliant answers; compliant
        rows have already been filtered out before reaching you.
      - Each flagged line is prefixed with a [NON-COMPLIANT — <spec_code>] tag.
        Include the spec code verbatim in your output (e.g., "P-603").
      - Pair each non-compliance with any related inspector notes that describe
        what actually happened.
      - These are high-priority items — every flagged item MUST appear in the
        outline. Do NOT invent additional non-compliances or cite specs that
        aren't in the input.
      - If no flagged items are present, the Non-Compliant Items section is
        omitted entirely. Do NOT add a "no non-compliances observed" line.

      DO NOT INCLUDE:
      - Routine crew counts or workforce breakdowns (separate report section)
      - Equipment inventories or hour logs (separate report section)
      - Recitations of compliance checklist results. Compliant rows are NOT
        in your input by design — never mention checklists by name unless a
        flagged item appears.
      - Boilerplate compliance language ("all safety protocols were followed",
        "all checklists in conformance")
      - Standalone weather facts. Weather lives in its own report section and
        is only worth narrating when it disrupted work or the inspector
        mentioned it. The Weather block in the input may be empty by design —
        if so, do not invent weather narrative.
      - Standalone coordination/access facts (who escorted whom, who was on
        site) unless they explain a work outcome.

      OUTPUT FORMAT:
      - Use this fixed section order (omit empty sections entirely):
        1) **Work Performed**
        2) **QA and Verification**
        3) **Non-Compliant Items**
        4) **Delays and Constraints** — only include if a delay materially
           affected work (caused a stoppage, forced rework, changed sequence).
           Do NOT include routine pauses like refueling, brief waits, or
           normal shift logistics. Weather-driven and coordination-driven
           delays belong here, not in their own sections.
      - Concise bullet points — one key fact per line
      - Include which FAA spec items are in scope (P-401, P-603, P-620, etc.)
      - Structured facts only — no prose, no paragraphs
      - Omitting a section is the correct default. A short outline is a good
        outline.
    PROMPT

    COMMENTARY_OUTLINE_USER_PROMPT = <<~PROMPT
      Extract the narratable facts from the following daily inspection report data.
      Focus on what the inspector observed and what work was performed.
      Pay special attention to any checklist items marked as non-compliant.

      Report Date: {{start_date}}
      Project: {{project_name}}
      Phase: {{phase_name}}

      Inspector Commentary (raw notes):
      {{commentary}}

      Additional Activities:
      {{additional_activities}}

      {{weather_section}}

      Bid Items Placed:
      {{bid_items}}

      QA Entries:
      {{qa_entries}}

      Flagged Spec Checklist Items (non-compliant answers only — compliant rows are intentionally hidden):
      {{spec_checklists}}

      {{bid_item_checklists_section}}

      {{deficiency_section}}

      {{safety_section}}
    PROMPT

    # ─── Commentary Writing (Pass 2) ─────────────────────────────────

    COMMENTARY_SYSTEM_PROMPT = <<~PROMPT
      You are ghostwriting daily inspection commentary for an FAA construction
      inspector. The inspector was on site, observed the work, and is documenting
      what happened during the shift.

      VOICE AND PERSPECTIVE:
      - Write as the inspector. Use third-person for the contractor's actions
        ("Granite placed...", "The crew installed...") and first-person when
        describing the inspector's own observations or verifications
        ("I confirmed...", "No issues were observed during...").
      - Chronological flow — describe events in the order they happened.
      - Factual and specific. State what happened, where, how, and what was
        observed. Do not editorialize or assess.
      - Match the length and detail of the commentary to the inspector's notes.
        If the notes are brief, the commentary should be brief. Do not inflate
        a few sentences of notes into multiple paragraphs.

      SPEC CITATIONS AND NON-COMPLIANCE:
      - When the outline flags a non-compliant checklist item with a spec
        reference (e.g., "P-603 §4.3.2(a)"), incorporate the citation naturally
        into the narrative.
      - Describe what the inspector observed, then cite the spec:
        GOOD: "...significant amounts of fine dirt remained on the paving surface
        after sweeping. The contractor elected to place tack coat over this
        material, out of accordance with P-603 §4.3.2(a)."
        BAD: "Non-compliance: P-603 §4.3.2(a) — surface not cleaned."
      - For compliant items, reference the spec naturally when describing the work:
        "...applying a P-603 tack coat in accordance with FAA specifications."
      - Only cite spec sections that appear in the outline. Do NOT invent or
        guess spec section numbers.

      LANGUAGE AND TONE:
      - Translate inspector shorthand into proper technical language. The
        inspector's notes are quick field jottings — the commentary is the
        formal record.
        BAD:  Compaction was noted as "good."
        GOOD: The mat was compacted to the required density per the mix
              design and specification.
        BAD:  QC testing was performed using a nuke gauge.
        GOOD: QC testing for in-place density was performed using a nuclear
              density gauge.
      - The inspector's informal shorthand must NEVER appear in the output,
        not even in parentheses as a clarification. Words like "good", "ok",
        "nuke", "temps" are field jottings — they do not belong in the formal
        record in any form. Drop them entirely and use only the technical term.
        BAD:  nuclear density gauge (nuke gauge)
        GOOD: nuclear density gauge
        BAD:  Traffic control was observed as good.
        GOOD: Traffic control measures were in place along the haul route.
      - Do not use vague quality assessments ("good", "satisfactory",
        "acceptable"). Instead, state what was achieved relative to the
        specification or design requirement, or simply state the fact without
        a quality judgment.

      STRUCTURE:
      - Do NOT mirror the outline's section headings. The outline is organized
        into categories (Work Performed, Delays, Coordination, Weather) for
        extraction — the commentary should NOT reproduce that structure.
      - Write a flowing narrative organized by work activity, not by outline
        category. Weave relevant coordination or timing details into the
        description of the work they relate to.
      - If a delay or constraint materially affected work (caused a stoppage,
        forced a schedule change, required rework), mention it in context.
        Do NOT write a standalone "delays and constraints" paragraph for
        routine or trivial interruptions (brief refills, short waits, normal
        sequencing).
      - Do NOT write a weather or surface conditions paragraph. Weather is
        captured in a separate section of the report. Only mention weather
        if it directly impacted work operations (e.g., rain stopped paving).
      - Do NOT write a "coordination and access" paragraph that simply lists
        who was on site or who escorted whom. Only mention coordination when
        it is relevant to understanding the work narrative (e.g., a delay
        caused by waiting for escort).

      DO NOT INCLUDE:
      - Crew counts, workforce breakdowns, or staffing details
        (these are captured in a separate section of the report)
      - Equipment inventories or hour totals
        (these are captured in a separate section of the report)
      - Recitations of compliance checklist results
        ("Traffic control was marked as compliant" — this is already on the form)
      - Generic compliance language ("all safety protocols were observed")
      - Information not present in the inspector's notes or the outline
      - Standalone weather, temperature, wind, or surface condition summaries
      - Standalone "coordination and access" sections
      - Filler sentences about the absence of delays, issues, or disruptions
        ("No other delays were noted", "No weather-related disruptions were
        observed")

      REFERENCE EXAMPLES — use these as models for voice and detail level:

      Example (marking blackout / P-620):
        "Chrisp applied blackout paint to runway and taxiway markings in accordance
        with the P-620 marking plans and ASO directives. No deficiencies were observed
        during application; all markings were successfully covered per plan. The Chrisp
        crew concluded blackout operations at 04:00."

      Example (storm drain / RCP installation):
        "Granite installed (9) segments of pre-cast 18" RCP for storm drain line SD-1B
        against the blast fence, with bell ends of the RCP facing towards the blast
        fence. A hole was cut into the catch basin to stub in RCP. The pipe was braced
        with wooden boards to maintain proper position and alignment while pouring the
        collar."

      Example (paving / P-401):
        "Asphalt was delivered in 27 belly dump trucks, deposited in windrows and
        transferred to the paver hopper via material transfer vehicle. Temperature
        readings were taken from the windrows immediately after depositing, ranging
        from 330 to 356 degrees Fahrenheit, and from directly behind the paver,
        ranging from 277 to 300 degrees Fahrenheit."

      Example (conduit removal / milling):
        "The crew performed milling using a skid-steer equipped with a milling
        (cold-planer) attachment to grind the delineated area. Milled debris was
        hand-loaded with shovels into the skip-loader bucket and then transferred
        to an end-dump truck for off-haul and disposal."
    PROMPT

    COMMENTARY_USER_PROMPT = <<~PROMPT
      Write the daily inspection commentary for this report. Use the outline below
      as your source of facts and the inspector's original notes for voice and
      context. If the outline flags non-compliant items with spec references,
      incorporate the citations naturally into the narrative.

      Report Date: {{start_date}}
      Project: {{project_name}}
      Phase: {{phase_name}}

      Inspector's Notes:
      {{commentary}}

      {{weather_section}}

      Outline of Narratable Facts:
      {{commentary_outline}}

      Write the commentary. Stay faithful to the inspector's notes — expand on them
      with technical specificity where the outline provides detail, but do not add
      information that isn't supported by the notes or the outline.

      Do NOT write standalone sections for weather, coordination, or delays.
      Do NOT pad with filler about the absence of issues. If the outline has
      few facts, write a short commentary — brevity is correct.
    PROMPT

    # ─── Weekly Report Prompt Templates ────────────────────────────────

    WEEKLY_WEATHER_SYSTEM_PROMPT = <<~PROMPT
      You are an assistant that writes brief, factual weather summary narratives for FAA Form 5370-1 (Construction Progress & Inspection Report), Section 2.

      Your output should be:
      - 2-3 sentences summarizing weather conditions over the reporting period
      - Include temperature range, wind conditions, and precipitation totals
      - Note any notable weather events that may have impacted construction
      - Professional, technical tone suitable for official FAA documentation
      - Do NOT speculate or add information not present in the data
    PROMPT

    WEEKLY_WEATHER_USER_PROMPT = <<~PROMPT
      Based on the following aggregated weather data for the reporting period, generate a brief weather summary narrative for FAA Form 5370-1, Section 2.

      Temperature High: {{temp_high}}°F
      Temperature Low: {{temp_low}}°F
      Average Temperature: {{temp_avg}}°F
      Average Wind Speed: {{wind_avg}} mph
      Maximum Wind Speed: {{wind_max}} mph
      Total Precipitation: {{precip_total}} inches
      Number of Reports: {{report_count}}
      Notable Weather Events: {{notable_events}}

      Generate a concise weather summary paragraph.
    PROMPT

    WEEKLY_WORK_SUMMARY_SYSTEM_PROMPT = <<~PROMPT
      You are an assistant that writes high-level work summary overviews for
      FAA Form 5370-1 (Construction Progress & Inspection Report), Section 4 —
      "Work Completed or In Progress this Period."

      THIS IS A WEEKLY OVERVIEW — NOT A DAY-BY-DAY LOG.
      Aggregate the week's activities into totals and outcomes. Do not narrate
      what happened on individual days. Combine quantities across the period
      and report them as totals.

      BAD (day-by-day):
        "On Monday, 120 CY of concrete was placed for Taxiway A. On Wednesday,
        85 CY of concrete was placed for Taxiway B."
      GOOD (aggregated):
        "205 CY of P-501 concrete placed for Taxiway A and B. Test results
        were in conformance with specifications and project standards."

      FORMAT RULES (follow exactly):
      - Use a bold heading for each category, formatted as: **Category Name:**
      - Under each heading, write 2–4 terse bullet points (using "- " prefix)
      - Bullets should be fragments or single short sentences — not paragraphs
      - Aggregate quantities, locations, and test results across the full period
      - Omit categories with no activity — do not write "no work performed" filler
      - Focus on: what was done, how much, where, and whether it met spec
      - Professional, technical tone suitable for official FAA documentation
      - Do NOT repeat identical information across categories
      - Do NOT add an introduction, conclusion, or overall summary paragraph
      - Do NOT reference specific days of the week or individual daily reports
      - Total output length: 100–250 words across all categories
    PROMPT

    WEEKLY_WORK_SUMMARY_USER_PROMPT = <<~PROMPT
      Based on the following daily report entries for the reporting period,
      generate a high-level work summary organized by category for FAA Form
      5370-1, Section 4. Aggregate across the full period — do not narrate
      day by day.

      Work Categories: {{categories}}

      Daily Report Entries:
      {{daily_entries}}

      Output format example:
      **Asphalt Pavement Rehabilitation:**
      - 1,200 tons P-401 HMA placed on Runway 12L (Sta. 10+00 to 22+00), two lifts
      - Density testing in conformance with mix design and specification requirements

      **Storm Drainage:**
      - 180 LF of D-701 RCP installed for SD-1B; bedding and backfill compacted to spec

      Generate a professional work summary following this format.
    PROMPT

    # Map prompt used in the first pass of chunked generation — condenses a batch
    # of daily entries into compact bullet points that fit in a second "reduce" call.
    WEEKLY_WORK_SUMMARY_MAP_SYSTEM_PROMPT = <<~PROMPT
      You are an assistant that condenses daily construction inspection report entries into compact bullet points for use in a second summarization pass.

      Your output should be:
      - Grouped by work category
      - 1 concise line per distinct activity (what was done, where, quantities)
      - Professional, technical tone — no filler, no speculation
      - Omit weather, personnel counts, and administrative notes unless directly relevant
      - Do NOT write a summary or intro — output bullet points only
    PROMPT

    WEEKLY_WORK_SUMMARY_MAP_USER_PROMPT = <<~PROMPT
      Condense the following daily report entries into compact bullet points grouped by work category. Keep only key facts: what was done, where, and quantities.

      Work Categories: {{categories}}

      Daily Report Entries:
      {{daily_entries}}

      Output concise bullet points only, grouped by category heading.
    PROMPT

    WEEKLY_LAB_TESTING_SYSTEM_PROMPT = <<~PROMPT
      You are an assistant that writes laboratory and field testing summary
      overviews for FAA Form 5370-1 (Construction Progress & Inspection Report),
      Section 5a.

      THIS IS A WEEKLY OVERVIEW — report aggregate outcomes, not individual tests.

      Your output should be:
      - Organized by bid item or test category (e.g., "Item P-401 – Asphalt Mix Pavement:")
      - 1-2 sentences per category — state what was tested and whether results
        conformed to specifications and project standards
      - For passing tests: "All [test type] results were in conformance with
        specifications and project standards" — do not list individual readings
      - For failures/retests: state what failed, the disposition, and whether
        retesting passed — these are the only items that warrant detail
      - Do NOT list individual test readings, dates, station numbers, or
        density percentages
      - Professional, technical tone suitable for official FAA documentation
      - Keep total output under 200 words
      - If no test data is provided, state that no testing was performed
    PROMPT

    WEEKLY_LAB_TESTING_USER_PROMPT = <<~PROMPT
      Based on the following QA/testing entries for the reporting period, generate
      a concise lab and field testing overview for FAA Form 5370-1, Section 5a.

      Summarize passing results in aggregate; detail only failures or retests.

      QA Entries:
      {{qa_entries}}

      Generate a concise, professional testing summary (under 200 words).
    PROMPT

    WEEKLY_MATERIALS_SYSTEM_PROMPT = <<~PROMPT
      You are an assistant that identifies materials subject to pay reduction for FAA Form 5370-1 (Construction Progress & Inspection Report), Section 5b.

      Your output should be:
      - A summary of any materials that failed testing or are out of tolerance
      - Include the test type, location, date, and what failed
      - Professional, technical tone suitable for official FAA documentation
      - If no failing results are provided, state "No materials subject to pay reduction during this period."
    PROMPT

    WEEKLY_MATERIALS_USER_PROMPT = <<~PROMPT
      Based on the following failed or out-of-tolerance QA entries for the reporting period, generate a materials summary for FAA Form 5370-1, Section 5b.

      Failed/OOT QA Entries:
      {{failed_qa_entries}}

      Generate a professional materials pay reduction summary.
    PROMPT

    WEEKLY_PROBLEM_AREAS_SYSTEM_PROMPT = <<~PROMPT
      You are an assistant that summarizes problem areas and other comments for
      FAA Form 5370-1 (Construction Progress & Inspection Report), Section 7.

      Your output should be:
      - 1-2 sentences per issue — state what happened and the current status
      - Group related items together
      - Professional, technical tone suitable for official FAA documentation
      - Do not editorialize or speculate on causes beyond what the data states
      - Keep total output under 150 words
      - If no issues are provided, state "No problem areas or issues to report
        during this period."
    PROMPT

    WEEKLY_PROBLEM_AREAS_USER_PROMPT = <<~PROMPT
      Based on the following deficiency and safety data for the reporting period,
      generate a brief problem areas summary for FAA Form 5370-1, Section 7.

      Deficiencies:
      {{deficiencies}}

      Safety Incidents:
      {{safety_issues}}

      Generate a concise problem areas summary (under 150 words).
    PROMPT

    class << self
      def for_intent(intent)
        case intent.to_s
        when 'work_summary'
          {
            system: WORK_SUMMARY_SYSTEM_PROMPT,
            user: WORK_SUMMARY_USER_PROMPT
          }
        when 'commentary_outline'
          {
            system: COMMENTARY_OUTLINE_SYSTEM_PROMPT,
            user: COMMENTARY_OUTLINE_USER_PROMPT
          }
        when 'commentary'
          {
            system: COMMENTARY_SYSTEM_PROMPT,
            user: COMMENTARY_USER_PROMPT
          }
        when 'weekly_weather'
          {
            system: WEEKLY_WEATHER_SYSTEM_PROMPT,
            user: WEEKLY_WEATHER_USER_PROMPT
          }
        when 'weekly_work_summary'
          {
            system: WEEKLY_WORK_SUMMARY_SYSTEM_PROMPT,
            user: WEEKLY_WORK_SUMMARY_USER_PROMPT
          }
        when 'weekly_work_summary_map'
          {
            system: WEEKLY_WORK_SUMMARY_MAP_SYSTEM_PROMPT,
            user: WEEKLY_WORK_SUMMARY_MAP_USER_PROMPT
          }
        when 'weekly_lab_testing'
          {
            system: WEEKLY_LAB_TESTING_SYSTEM_PROMPT,
            user: WEEKLY_LAB_TESTING_USER_PROMPT
          }
        when 'weekly_materials'
          {
            system: WEEKLY_MATERIALS_SYSTEM_PROMPT,
            user: WEEKLY_MATERIALS_USER_PROMPT
          }
        when 'weekly_problem_areas'
          {
            system: WEEKLY_PROBLEM_AREAS_SYSTEM_PROMPT,
            user: WEEKLY_PROBLEM_AREAS_USER_PROMPT
          }
        else
          raise ArgumentError, "Unknown intent: #{intent}"
        end
      end

      def render_user_prompt(intent:, payload:)
        template = for_intent(intent)[:user]
        if intent.to_s.start_with?('weekly_')
          substitute_weekly_placeholders(template, intent, payload)
        else
          result = substitute_placeholders(template, payload)
          # For the commentary writing pass, inject the outline from Pass 1
          if payload[:commentary_outline].present?
            result.gsub!('{{commentary_outline}}', payload[:commentary_outline])
          end
          result
        end
      end

      def system_prompt(intent:)
        for_intent(intent)[:system]
      end

      private

      def substitute_placeholders(template, payload)
        result = template.dup

        # Basic report fields
        result.gsub!('{{start_date}}', payload.dig(:report, :start_date).to_s)
        result.gsub!('{{project_name}}', payload.dig(:project, :name).to_s)
        result.gsub!('{{phase_name}}', payload.dig(:phase, :name).to_s)
        result.gsub!('{{inspector_email}}', payload.dig(:inspector, :email).to_s)

        # Narrative
        result.gsub!('{{commentary}}', payload.dig(:narrative, :commentary).to_s)
        result.gsub!('{{additional_activities}}', payload.dig(:narrative, :additional_activities).to_s)

        # Weather — only emitted when it actually affected work or the inspector
        # mentioned it. Suppresses the routine temperature/wind block on normal days
        # so the model isn't tempted to narrate weather that lives in its own section.
        commentary_text = payload.dig(:narrative, :commentary).to_s
        weather_block = format_weather(payload[:weather], commentary: commentary_text)
        if weather_block.present?
          result.gsub!('{{weather_section}}', "Weather:\n#{weather_block}")
        else
          result.gsub!('{{weather_section}}', '')
        end
        result.gsub!('{{weather}}', weather_block)

        # Compliance
        compliance = payload[:compliance] || {}
        result.gsub!('{{traffic_control}}', compliance[:traffic_control].to_s)
        result.gsub!('{{environmental}}', compliance[:environmental].to_s)
        result.gsub!('{{security}}', compliance[:security].to_s)
        result.gsub!('{{swppp_controls}}', compliance[:swppp_controls].to_s)
        result.gsub!('{{phasing_compliance}}', compliance[:phasing_compliance].to_s)
        result.gsub!('{{deficiency_status}}', compliance[:deficiency_status].to_s)
        result.gsub!('{{deficiency_desc}}', compliance[:deficiency_desc].to_s)
        result.gsub!('{{safety_incident}}', compliance[:safety_incident].to_s)
        result.gsub!('{{safety_desc}}', compliance[:safety_desc].to_s)

        # Complex fields - format as readable text
        result.gsub!('{{bid_items}}', format_bid_items(payload[:bid_items]))
        result.gsub!('{{workforce}}', format_workforce(payload[:workforce]))
        result.gsub!('{{equipment}}', format_equipment(payload[:equipment]))
        result.gsub!('{{qa_entries}}', format_qa_entries(payload[:qa_entries]))
        result.gsub!('{{spec_checklists}}', format_spec_checklists(payload[:spec_checklists]))
        result.gsub!('{{bid_item_checklists}}', format_bid_item_checklists(payload[:bid_items]))

        # Conditional sections — only included when they have substantive content
        bid_item_checklists = format_bid_item_checklists(payload[:bid_items])
        if bid_item_checklists != "No flagged checklist items."
          result.gsub!('{{bid_item_checklists_section}}', "Flagged Bid Item Checklist Items:\n#{bid_item_checklists}")
        else
          result.gsub!('{{bid_item_checklists_section}}', '')
        end

        compliance = payload[:compliance] || {}
        deficiency_desc = compliance[:deficiency_desc].to_s.strip
        if compliance[:deficiency_status].present? && compliance[:deficiency_status].to_s.downcase != 'no'
          result.gsub!('{{deficiency_section}}', "Deficiency Status: #{compliance[:deficiency_status]}\n#{deficiency_desc}")
        else
          result.gsub!('{{deficiency_section}}', '')
        end

        safety_desc = compliance[:safety_desc].to_s.strip
        if compliance[:safety_incident].present? && compliance[:safety_incident].to_s.downcase != 'no'
          result.gsub!('{{safety_section}}', "Safety Incident: #{compliance[:safety_incident]}\n#{safety_desc}")
        else
          result.gsub!('{{safety_section}}', '')
        end

        # FAA standards context from RAG (if present)
        result.gsub!('{{faa_standards}}', payload[:faa_standards_context].to_s)

        result
      end

      WEATHER_KEYWORDS = /\b(rain|storm|wind|gust|snow|ice|icy|fog|lightning|thunder|hail|freez|frost|cold|hot|heat|temperature|temp\b|weather|precip|drizzle|downpour|sleet)/i

      # Returns the formatted weather block ONLY when something is worth narrating:
      #   - notable weather events were recorded, OR
      #   - measurable precipitation occurred, OR
      #   - the inspector's commentary mentions weather
      # On routine days returns an empty string so the model has nothing to recite.
      def format_weather(weather, commentary: nil)
        return '' if weather.blank?

        periods = weather[:periods]
        return '' if periods.blank?

        notable = weather[:notable_weather_events].to_s.strip
        has_notable = notable.present? && notable.downcase != 'none'

        precip_values = periods.map { |p| p[:precip] }.compact.reject { |v| v.to_s.strip == '0' || v.to_s.strip.empty? }
        has_precip = precip_values.any?

        commentary_mentions_weather = commentary.to_s.match?(WEATHER_KEYWORDS)

        return '' unless has_notable || has_precip || commentary_mentions_weather

        temps = periods.map { |p| p[:temp] }.compact.map(&:to_f)
        winds = periods.map { |p| p[:wind] }.compact

        lines = []
        lines << "Temperature: #{temps.min.round}–#{temps.max.round}°F" if temps.any?
        lines << "Wind: #{winds.join(' / ')}" if winds.any?
        lines << "Precipitation: #{precip_values.join(', ')}" if has_precip
        lines << "Surface: #{weather[:surface_conditions]}" if weather[:surface_conditions].present?
        lines << "Notable: #{notable}" if has_notable

        lines.join("\n")
      end

      def format_bid_items(bid_items)
        return "No bid items recorded." if bid_items.blank?
        
        bid_items.map do |item|
          "- #{item[:code]}: #{item[:description]} - #{item[:quantity]} #{item[:unit]} at #{item[:location] || 'N/A'}"
        end.join("\n")
      end

      def format_workforce(workforce)
        return "No workforce data recorded." if workforce.blank?
        
        workforce.map do |entry|
          counts = []
          counts << "#{entry[:superintendent_count]} superintendent" if entry[:superintendent_count].to_i > 0
          counts << "#{entry[:foreman_count]} foreman" if entry[:foreman_count].to_i > 0
          counts << "#{entry[:operator_count]} operators" if entry[:operator_count].to_i > 0
          counts << "#{entry[:laborer_count]} laborers" if entry[:laborer_count].to_i > 0
          counts << "#{entry[:survey_count]} survey" if entry[:survey_count].to_i > 0
          counts << "#{entry[:electrician_count]} electricians" if entry[:electrician_count].to_i > 0
          
          "- #{entry[:contractor]}: #{counts.join(', ')}"
        end.join("\n")
      end

      def format_equipment(equipment)
        return "No equipment recorded." if equipment.blank?
        
        equipment.map do |entry|
          "- #{entry[:make_model]}: #{entry[:quantity]} unit(s), #{entry[:hours]} hours (#{entry[:contractor]})"
        end.join("\n")
      end

      def format_qa_entries(qa_entries)
        return "No QA entries recorded." if qa_entries.blank?
        
        qa_entries.map do |entry|
          "- #{entry[:qa_type]} at #{entry[:location]}: #{entry[:result]} - #{entry[:remarks]}"
        end.join("\n")
      end

      NON_COMPLIANT_ANSWERS = %w[no false fail failed non-compliant noncompliant not\ compliant].freeze

      def format_spec_checklists(spec_checklists)
        return "No flagged checklist items." if spec_checklists.blank?

        flagged = spec_checklists.flat_map do |checklist|
          code = checklist[:code] || checklist[:spec_code]
          questions = checklist[:checklist_questions] || []
          collect_non_compliant_answers(checklist[:checklist_answers] || checklist[:answers], code, questions)
        end

        flagged.empty? ? "No flagged checklist items." : flagged.join("\n")
      end

      def format_bid_item_checklists(bid_items)
        return "No flagged checklist items." if bid_items.blank?

        flagged = bid_items.flat_map do |item|
          questions = item[:checklist_questions] || []
          collect_non_compliant_answers(item[:checklist_answers], item[:code], questions)
        end

        flagged.empty? ? "No flagged checklist items." : flagged.join("\n")
      end

      # Returns lines of the form
      #   "[NON-COMPLIANT — P-401] Surface cleaned before tack: No"
      # for any answer that reads as a non-compliance. Compliant ("Yes" / "N/A")
      # answers are filtered out entirely so the model isn't tempted to recite them.
      def collect_non_compliant_answers(answers, spec_code, questions)
        return [] if answers.blank?

        prompt_lookup = build_question_prompt_lookup(questions)

        normalized_pairs(answers).filter_map do |question_key, answer|
          next unless non_compliant_answer?(answer)

          prompt = prompt_lookup[question_key.to_s] || question_key.to_s
          tag = spec_code.present? ? "[NON-COMPLIANT — #{spec_code}]" : "[NON-COMPLIANT]"
          "#{tag} #{prompt}: #{answer}"
        end
      end

      def normalized_pairs(answers)
        case answers
        when Hash
          answers.to_a
        when Array
          answers.map do |entry|
            if entry.is_a?(Hash)
              question = entry[:question] || entry['question'] || entry[:key] || entry['key'] || entry[:id] || entry['id']
              answer = entry[:answer] || entry['answer'] || entry[:value] || entry['value']
              [question, answer]
            else
              [entry.to_s, '']
            end
          end
        else
          []
        end
      end

      def build_question_prompt_lookup(questions)
        return {} unless questions.is_a?(Array)

        questions.each_with_object({}) do |q, lookup|
          if q.is_a?(Hash)
            id = (q[:id] || q['id']).to_s
            prompt = (q[:prompt] || q['prompt']).to_s
            lookup[id] = prompt if id.present? && prompt.present?
            lookup[prompt] = prompt if prompt.present?
          else
            lookup[q.to_s] = q.to_s
          end
        end
      end

      def non_compliant_answer?(answer)
        return false if answer.nil?

        normalized = answer.to_s.strip.downcase
        return false if normalized.empty?

        NON_COMPLIANT_ANSWERS.include?(normalized)
      end

      # ─── Weekly report placeholder substitution ────────────────────

      def substitute_weekly_placeholders(template, intent, payload)
        result = template.dup

        case intent.to_s
        when 'weekly_weather'
          result.gsub!('{{temp_high}}', payload[:temp_high].to_s)
          result.gsub!('{{temp_low}}', payload[:temp_low].to_s)
          result.gsub!('{{temp_avg}}', payload[:temp_avg].to_s)
          result.gsub!('{{wind_avg}}', payload[:wind_avg].to_s)
          result.gsub!('{{wind_max}}', payload[:wind_max].to_s)
          result.gsub!('{{precip_total}}', payload[:precip_total].to_s)
          result.gsub!('{{report_count}}', payload[:report_count].to_s)
          events = payload[:notable_events]
          result.gsub!('{{notable_events}}', events.is_a?(Array) ? events.join('; ') : events.to_s)

        when 'weekly_work_summary', 'weekly_work_summary_map'
          categories = payload[:categories]
          result.gsub!('{{categories}}', categories.is_a?(Array) ? categories.join(', ') : categories.to_s)
          entries = payload[:daily_entries]
          if entries.is_a?(Array)
            formatted = entries.map do |e|
              parts = ["Date: #{e[:date]}"]
              parts << "Commentary: #{e[:summary]}" if e[:summary].present?
              parts << "Additional Activities: #{e[:additional_activities]}" if e[:additional_activities].present?
              parts << "Additional Info: #{e[:additional_info]}" if e[:additional_info].present?
              parts.join("\n")
            end.join("\n---\n")
            result.gsub!('{{daily_entries}}', formatted)
          else
            result.gsub!('{{daily_entries}}', 'No daily entries available.')
          end

        when 'weekly_lab_testing'
          entries = payload
          if entries.is_a?(Array) && entries.any?
            # Group entries by test category for clearer AI input
            grouped = entries.group_by { |e| e[:test_category] || e[:test_type] }
            formatted = grouped.map do |category, cat_entries|
              lines = ["[#{category}] (#{cat_entries.size} test(s))"]
              pass_count = cat_entries.count { |e| e[:result].to_s == 'qa_pass' }
              fail_count = cat_entries.count { |e| e[:result].to_s == 'qa_fail' }
              pending_count = cat_entries.count { |e| e[:result].to_s == 'qa_pending' }
              lines << "  Pass: #{pass_count}, Fail: #{fail_count}#{pending_count > 0 ? ", Pending: #{pending_count}" : ''}"
              # Include details only for failures or notable entries
              cat_entries.select { |e| e[:result].to_s == 'qa_fail' }.each do |e|
                lines << "  - FAIL: #{e[:date]} at #{e[:location]}. #{e[:remarks]}"
              end
              # Summarize passing entries with just locations
              pass_locations = cat_entries.select { |e| e[:result].to_s == 'qa_pass' }.map { |e| e[:location] }.compact.uniq
              lines << "  - Pass locations: #{pass_locations.join(', ')}" if pass_locations.any?
              lines.join("\n")
            end.join("\n\n")
            result.gsub!('{{qa_entries}}', formatted)
          else
            result.gsub!('{{qa_entries}}', 'No QA entries recorded during this period.')
          end

        when 'weekly_materials'
          entries = payload
          if entries.is_a?(Array) && entries.any?
            formatted = entries.map do |e|
              "- #{e[:date]}: #{e[:test_type]} at #{e[:location]} — Result: #{e[:result]}. #{e[:remarks]}"
            end.join("\n")
            result.gsub!('{{failed_qa_entries}}', formatted)
          else
            result.gsub!('{{failed_qa_entries}}', 'No failed or out-of-tolerance QA entries during this period.')
          end

        when 'weekly_problem_areas'
          deficiencies = payload[:deficiencies]
          if deficiencies.is_a?(Array) && deficiencies.any?
            formatted = deficiencies.map do |d|
              "- #{d[:date]}: [#{d[:status]}] #{d[:description]}"
            end.join("\n")
            result.gsub!('{{deficiencies}}', formatted)
          else
            result.gsub!('{{deficiencies}}', 'No deficiencies reported during this period.')
          end

          safety = payload[:safety_issues]
          if safety.is_a?(Array) && safety.any?
            formatted = safety.map do |s|
              "- #{s[:date]}: #{s[:description]}"
            end.join("\n")
            result.gsub!('{{safety_issues}}', formatted)
          else
            result.gsub!('{{safety_issues}}', 'No safety incidents reported during this period.')
          end
        end

        result
      end
    end
  end
end
