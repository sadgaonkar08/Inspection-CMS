require "caxlsx"

class P610QaqcXlsxExporter
  COLUMN_WIDTHS_28 = {
    "A" => 11.73, "B" => 11.73, "C" => 11.73, "D" => 11.54, "E" => 7.45,
    "F" => 48.63, "G" => 6.54, "H" => 9.73, "I" => 6.45, "J" => 8.54,
    "K" => 8.54, "L" => 10.0, "M" => 8.54, "N" => 10.09, "O" => 10.09,
    "P" => 8.82, "Q" => 11.54, "R" => 11.54, "S" => 12.18, "T" => 37.27,
    "U" => 18.54, "V" => 23.18, "W" => 11.54, "X" => 16.27, "Y" => 14.18
  }.freeze

  COLUMN_WIDTHS_HES = {
    "A" => 11.73, "B" => 11.73, "C" => 11.73, "D" => 14.0, "E" => 11.54,
    "F" => 7.45, "G" => 48.63, "H" => 6.54, "I" => 9.73, "J" => 6.45,
    "K" => 8.54, "L" => 8.54, "M" => 10.0, "N" => 8.54, "O" => 10.09,
    "P" => 10.09, "Q" => 8.82, "R" => 11.54, "S" => 11.54, "T" => 12.18,
    "U" => 37.27, "V" => 18.54
  }.freeze

  HEADERS_28 = [
    "Sample Date", "QA Lab ID.", "QC Lab ID.", "Supplier ", "Mix ID",
    "Source of Sample", "Sample", "Date tested", "Age (Days)",
    "Actual\nQA", "Actual\nQC", "Design strength", "Pass/Fail?",
    "Slump\nQA", "Slump\nQC", "Slump\nPass/Fail",
    "Air Content\nQA", "Air Content\nQC", "Air Content\nPass/Fail",
    "Remark", "Sample By", "Submittal #", "MIX ", "Manufacturer ", "air content "
  ].freeze

  HEADERS_HES = [
    "Sample Date", "QA Lab ID.", "QC Lab ID.", "Truck Ticket", "Supplier ",
    "Mix ID", "Source of Sample", "Sample", "Date tested", "Age (Days)",
    "Actual\nQA", "Actual\nQC", "Design strength", "Pass/Fail?",
    "Spread\nQA", "Spread\nQC", "Slump\nPass/Fail",
    "Air Content\nQA", "Air Content\nQC", "Air Content\nPass/Fail",
    "Remark", "Sample By"
  ].freeze

  SAMPLE_LABELS = %w[A B C D E].freeze

  def initialize(results)
    @results = results
  end

  def build
    package = Axlsx::Package.new
    wb = package.workbook

    styles = build_styles(wb)

    standard_rows = @results.reject(&:hes).map { |r| P610Export::Serializer.new(r).call }
    hes_rows = @results.select(&:hes).map { |r| P610Export::Serializer.new(r).call }

    build_sheet(wb, "P-610 28-Day", HEADERS_28, COLUMN_WIDTHS_28, standard_rows, styles, variant: :standard)
    build_sheet(wb, "P-610 HES", HEADERS_HES, COLUMN_WIDTHS_HES, hes_rows, styles, variant: :hes)

    package
  end

  private

  def build_styles(wb)
    styles = wb.styles
    {
      header: styles.add_style(
        b: true, sz: 10,
        alignment: { horizontal: :center, vertical: :center, wrap_text: true },
        border: { style: :thin, color: "000000" },
        bg_color: "D9E1F2"
      ),
      cell: styles.add_style(
        sz: 10,
        alignment: { horizontal: :center, vertical: :center, wrap_text: true },
        border: { style: :thin, color: "000000" }
      ),
      date_cell: styles.add_style(
        sz: 10, format_code: "m/d/yyyy",
        alignment: { horizontal: :center, vertical: :center },
        border: { style: :thin, color: "000000" }
      ),
      num_cell: styles.add_style(
        sz: 10, format_code: "#,##0",
        alignment: { horizontal: :center, vertical: :center },
        border: { style: :thin, color: "000000" }
      ),
      source_cell: styles.add_style(
        sz: 10,
        alignment: { horizontal: :left, vertical: :center, wrap_text: true },
        border: { style: :thin, color: "000000" }
      )
    }
  end

  def build_sheet(wb, name, headers, widths, rows, styles, variant:)
    wb.add_worksheet(name: name) do |sheet|
      sheet.add_row headers, style: styles[:header], height: 33.5

      width_array = Array.new(headers.size)
      widths.each { |col, w| width_array[col.ord - "A".ord] = w }
      sheet.column_widths(*width_array)

      next_row = 2
      rows.each do |row_data|
        next_row = add_sample_block(sheet, row_data, next_row, styles, variant)
      end
    end
  end

  def add_sample_block(sheet, row_data, start_row, styles, variant)
    cyls = row_data[:cylinders]
    cyls = [{ label: "A", age_days: nil, date_tested: nil, actual_qa_psi: nil }] if cyls.empty?

    block_size = cyls.size
    end_row = start_row + block_size - 1

    cyls.each_with_index do |c, i|
      r = start_row + i
      is_first = (i == 0)

      if variant == :standard
        sheet.add_row(
          build_standard_row(row_data, c, r, is_first),
          style: standard_row_styles(styles),
          height: 15.0
        )
      else
        sheet.add_row(
          build_hes_row(row_data, c, r, is_first),
          style: hes_row_styles(styles),
          height: 15.0
        )
      end
    end

    if block_size > 1
      merge_block_columns(sheet, start_row, end_row, variant)
    end

    end_row + 1
  end

  # === P-610 28-Day variant =================================================

  def build_standard_row(row_data, cyl, row_num, is_first)
    [
      is_first ? row_data[:sample_date] : nil,       # A Sample Date
      is_first ? row_data[:qa_lab_id] : nil,          # B QA Lab ID
      is_first ? row_data[:qc_lab_id] : nil,          # C QC Lab ID
      is_first ? row_data[:supplier] : nil,           # D Supplier
      is_first ? row_data[:mix_id] : nil,             # E Mix ID
      is_first ? row_data[:source_of_sample] : nil,   # F Source of Sample
      cyl[:label],                                    # G Sample
      cyl[:date_tested],                              # H Date tested
      cyl[:age_days],                                 # I Age (Days)
      cyl[:actual_qa_psi],                            # J Actual QA
      nil,                                            # K Actual QC
      is_first ? row_data[:design_strength_psi] : nil, # L Design strength
      pass_fail_formula("J", "L", row_num),           # M Pass/Fail
      is_first ? row_data[:slump_qa] : nil,           # N Slump QA
      is_first ? row_data[:slump_qc] : nil,           # O Slump QC
      is_first ? slump_formula(row_num, "N", "O") : nil, # P Slump Pass/Fail
      is_first ? row_data[:air_content_qa] : nil,     # Q Air Content QA
      is_first ? row_data[:air_content_qc] : nil,     # R Air Content QC
      is_first ? air_formula(row_num, "Q", "R") : nil, # S Air Content Pass/Fail
      is_first ? row_data[:remark] : nil,             # T Remark
      is_first ? row_data[:sample_by] : nil,          # U Sample By
      is_first ? row_data[:submittal_number] : nil,   # V Submittal #
      is_first ? row_data[:mix_id] : nil,             # W MIX
      is_first ? row_data[:manufacturer] : nil,       # X Manufacturer
      is_first ? row_data[:air_content_qa] : nil      # Y air content
    ]
  end

  def standard_row_styles(styles)
    [
      styles[:date_cell],  # A
      styles[:cell],       # B
      styles[:cell],       # C
      styles[:cell],       # D
      styles[:cell],       # E
      styles[:source_cell], # F
      styles[:cell],       # G
      styles[:date_cell],  # H
      styles[:cell],       # I
      styles[:num_cell],   # J
      styles[:num_cell],   # K
      styles[:num_cell],   # L
      styles[:cell],       # M
      styles[:cell],       # N
      styles[:cell],       # O
      styles[:cell],       # P
      styles[:cell],       # Q
      styles[:cell],       # R
      styles[:cell],       # S
      styles[:source_cell], # T
      styles[:cell],       # U
      styles[:cell],       # V
      styles[:cell],       # W
      styles[:cell],       # X
      styles[:cell]        # Y
    ]
  end

  # === P-610 HES variant ====================================================

  def build_hes_row(row_data, cyl, row_num, is_first)
    [
      is_first ? row_data[:sample_date] : nil,       # A Sample Date
      is_first ? row_data[:qa_lab_id] : nil,          # B QA Lab ID
      is_first ? row_data[:qc_lab_id] : nil,          # C QC Lab ID
      is_first ? row_data[:truck_ticket] : nil,       # D Truck Ticket
      is_first ? row_data[:supplier] : nil,           # E Supplier
      is_first ? row_data[:mix_id] : nil,             # F Mix ID
      is_first ? row_data[:source_of_sample] : nil,   # G Source of Sample
      cyl[:label],                                    # H Sample
      cyl[:date_tested],                              # I Date tested
      cyl[:age_days],                                 # J Age (Days)
      cyl[:actual_qa_psi],                            # K Actual QA
      nil,                                            # L Actual QC
      is_first ? row_data[:design_strength_psi] : nil, # M Design strength
      pass_fail_formula("K", "M", row_num),           # N Pass/Fail
      is_first ? row_data[:slump_qa] : nil,           # O Spread QA
      is_first ? row_data[:slump_qc] : nil,           # P Spread QC
      is_first ? hes_spread_formula(row_num) : nil,   # Q Slump Pass/Fail
      is_first ? row_data[:air_content_qa] : nil,     # R Air Content QA
      is_first ? row_data[:air_content_qc] : nil,     # S Air Content QC
      is_first ? hes_air_formula(row_num) : nil,      # T Air Content Pass/Fail
      is_first ? row_data[:remark] : nil,             # U Remark
      is_first ? row_data[:sample_by] : nil           # V Sample By
    ]
  end

  def hes_row_styles(styles)
    [
      styles[:date_cell],  # A
      styles[:cell],       # B
      styles[:cell],       # C
      styles[:cell],       # D
      styles[:cell],       # E
      styles[:cell],       # F
      styles[:source_cell], # G
      styles[:cell],       # H
      styles[:date_cell],  # I
      styles[:cell],       # J
      styles[:num_cell],   # K
      styles[:num_cell],   # L
      styles[:num_cell],   # M
      styles[:cell],       # N
      styles[:cell],       # O
      styles[:cell],       # P
      styles[:cell],       # Q
      styles[:cell],       # R
      styles[:cell],       # S
      styles[:cell],       # T
      styles[:source_cell], # U
      styles[:cell]        # V
    ]
  end

  # === Formulas + merges ====================================================

  def pass_fail_formula(actual_col, design_col, row_num)
    "=IF(OR(#{actual_col}#{row_num}>=#{design_col}#{row_num}, ISBLANK(#{actual_col}#{row_num})),\"Pass\",\"Fail\")"
  end

  def slump_formula(row_num, qa_col, qc_col)
    "=IF(OR(ISBLANK(#{qa_col}#{row_num})),\"\",IF(AND(#{qa_col}#{row_num}<=5,#{qa_col}#{row_num}>=3),\"Pass\",\"Fail\"))"
  end

  def air_formula(row_num, qa_col, qc_col)
    "=IF(#{qa_col}#{row_num}=\"\",\"\",IF(AND(#{qa_col}#{row_num}>=3.8,#{qa_col}#{row_num}<=6.2),\"PASS\",\"FAIL\"))"
  end

  def hes_spread_formula(row_num)
    "=IF(OR(ISBLANK(O#{row_num})),\"\",IF(AND(O#{row_num}<=4, P#{row_num}<=4),\"Pass\",\"Fail\"))"
  end

  def hes_air_formula(row_num)
    "=IF(OR(ISBLANK(R#{row_num})),\"\",IF(AND(R#{row_num}<=6.2, S#{row_num}<=6.2),\"Pass\",\"Fail\"))"
  end

  def merge_block_columns(sheet, start_row, end_row, variant)
    cols = variant == :standard ?
      %w[A B C D E F N O P Q R S T U V W X Y] :
      %w[A B C D E F G O P Q R S T U V]
    cols.each do |col|
      sheet.merge_cells("#{col}#{start_row}:#{col}#{end_row}")
    end
  end
end
