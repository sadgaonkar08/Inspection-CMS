require "tempfile"

class LabTestExtractionJob < ApplicationJob
  queue_as :lab_extraction

  MAX_RAW_TEXT_BYTES = 200_000

  def perform(lab_test_import_id)
    import = LabTestImport.find_by(id: lab_test_import_id)
    unless import
      Rails.logger.warn("LabTestExtractionJob skipped: import #{lab_test_import_id} no longer exists")
      return
    end

    unless import.source_pdf.attached?
      mark_rejected!(import, ["source_pdf_missing"])
      return
    end

    Tempfile.create(["lab_test_pdf_", ".pdf"], binmode: true) do |tmp|
      import.source_pdf.download { |chunk| tmp.write(chunk) }
      tmp.flush

      payload = PythonPdfExtractor.extract(pdf_path: tmp.path, spec_code: import.spec_code)
      finalize(import, payload)
    end
  rescue PythonPdfExtractor::ExtractionError => e
    Rails.logger.error("LabTestExtractionJob extractor error for import #{lab_test_import_id}: #{e.message}")
    errors = Array(e.payload["errors"]).presence || [e.message]
    mark_rejected!(import, errors) if import&.persisted?
  rescue => e
    Rails.logger.error("LabTestExtractionJob failed for import #{lab_test_import_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    mark_rejected!(import, [e.message]) if import&.persisted?
  end

  private

  def finalize(import, payload)
    rows = Array(payload["rows"])
    errors = Array(payload["errors"])
    header = payload["header"] || {}
    raw_text = payload["raw_text"].to_s[0, MAX_RAW_TEXT_BYTES]

    ActiveRecord::Base.transaction do
      import.update!(
        lab_name: header["lab_name"],
        report_header: header,
        parsed_data: rows,
        extraction_errors: errors,
        row_count: rows.size,
        raw_text: raw_text
      )

      if errors.empty? && rows.any? && all_required_fields_present?(import.spec_code, rows)
        persist_results(import, rows, header)
        import.update!(status: "saved")
      else
        import.update!(status: "needs_review")
      end
    end

    import.broadcast_status
  end

  def persist_results(import, rows, header)
    rows.each do |row|
      import.lab_test_results.create!(
        project_id:     import.project_id,
        asphalt_lot_id: import.asphalt_lot_id,
        report_id:      import.report_id,
        spec_code:      import.spec_code,
        lab_name:       header["lab_name"],
        report_date:    parse_date(header["report_date"]),
        test_date:      parse_date(row["test_date"]) || parse_date(header["report_date"]),
        sublot_number:  row["sublot_number"],
        result:         row["result"],
        data:           row
      )
    end
  end

  def all_required_fields_present?(spec_code, rows)
    rows.all? { |row| REQUIRED_FIELDS.fetch(spec_code, []).all? { |f| row[f].present? || row[f] == false } }
  end

  REQUIRED_FIELDS = {
    "P-401" => %w[sublot_number test_date gmb_avg gmm_avg air_voids_avg air_voids_min_pct air_voids_max_pct result],
    "P-403" => %w[sublot_number core_id core_type gmb gmm compaction_pct required_compaction_pct result],
    # P-610 may legitimately have nil result/avg_strength when 28-day breaks are still pending,
    # so we don't require those here — only the structural fields that should always be present.
    "P-610" => %w[lab_id_number specified_strength_psi cylinders]
  }.freeze

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def mark_rejected!(import, errors)
    import.update!(status: "rejected", extraction_errors: errors)
    import.broadcast_status
  end
end
