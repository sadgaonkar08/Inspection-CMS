require "json"
require "open3"

class PythonPdfExtractor
  class ExtractionError < StandardError
    attr_reader :payload
    def initialize(message, payload: {})
      super(message)
      @payload = payload
    end
  end

  # Exit codes mirror python/extract_lab_report.py:
  #   0 = success (may include listed errors)
  #   2 = no_text_scanned
  #   3 = unknown_lab
  #   4 = bad_args
  STRUCTURED_EXIT_CODES = [0, 2, 3].freeze

  def self.extract(pdf_path:, spec_code:)
    raise ArgumentError, "pdf_path required" if pdf_path.blank?
    raise ArgumentError, "spec_code required" if spec_code.blank?

    script = Rails.root.join("python", "extract_lab_report.py")
    raise ExtractionError, "Extractor script not found: #{script}" unless File.exist?(script)

    python_cmd = resolve_python_cmd

    stdout, stderr, status = Open3.capture3(
      python_cmd.to_s, script.to_s,
      "--pdf", pdf_path.to_s,
      "--spec", spec_code.to_s
    )

    if STRUCTURED_EXIT_CODES.include?(status.exitstatus)
      parse_payload(stdout, stderr, status.exitstatus)
    else
      Rails.logger.error("PythonPdfExtractor: unexpected exit #{status.exitstatus}")
      Rails.logger.error("STDOUT: #{stdout}")
      Rails.logger.error("STDERR: #{stderr}")
      raise ExtractionError.new(
        "PDF extraction failed (exit #{status.exitstatus}): #{stderr.strip.lines.last.to_s.strip}",
        payload: { "errors" => ["extractor_crashed"] }
      )
    end
  end

  def self.resolve_python_cmd
    venv_python = Rails.root.join(".venv", "bin", "python")
    venv_python3 = Rails.root.join(".venv", "bin", "python3")
    cmd = [venv_python, venv_python3].find { |path| File.exist?(path) }
    unless cmd
      Rails.logger.warn("PythonPdfExtractor: .venv interpreter not found, falling back to system python3")
      return "python3"
    end
    cmd
  end

  def self.parse_payload(stdout, stderr, exit_code)
    payload = JSON.parse(stdout)
    payload["exit_code"] = exit_code
    payload
  rescue JSON::ParserError => e
    Rails.logger.error("PythonPdfExtractor: could not parse JSON output: #{e.message}")
    Rails.logger.error("STDOUT: #{stdout}")
    Rails.logger.error("STDERR: #{stderr}")
    raise ExtractionError.new("Extractor returned invalid JSON", payload: { "errors" => ["invalid_json"] })
  end
end
