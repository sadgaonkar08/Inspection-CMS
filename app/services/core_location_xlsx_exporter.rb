# frozen_string_literal: true

require "caxlsx"

class CoreLocationXlsxExporter
  def initialize(core_generation, lot)
    @core_generation = core_generation
    @lot = lot
  end

  def to_stream
    locations = @core_generation.core_locations
                  .includes(:asphalt_sublot, :asphalt_lane, :left_lane, :right_lane)
                  .to_a
                  .sort_by do |loc|
                    [
                      loc.asphalt_sublot&.position || Float::INFINITY,
                      loc.joint? ? 0 : 1,
                      loc.mark.to_s
                    ]
                  end
    sublot_positions = locations.map { |loc| loc.asphalt_sublot&.position }.compact.uniq.sort

    package = Axlsx::Package.new
    workbook = package.workbook
    styles = workbook.styles

    mat_bg = "CCFFFF"
    joint_bg = "FFD9B3"
    dist_bg = "BFBFBF"

    header_style = styles.add_style(
      b: true, bg_color: "FFFFFF", fg_color: "000000",
      alignment: { horizontal: :center, vertical: :center },
      border: Axlsx::STYLE_THIN_BORDER
    )

    text_left_mat = styles.add_style(bg_color: mat_bg, alignment: { horizontal: :left, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    text_left_joint = styles.add_style(bg_color: joint_bg, alignment: { horizontal: :left, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    text_left_mat_bold = styles.add_style(bg_color: mat_bg, b: true, alignment: { horizontal: :left, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    text_left_joint_bold = styles.add_style(bg_color: joint_bg, b: true, alignment: { horizontal: :left, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    num_right_mat = styles.add_style(bg_color: mat_bg, num_fmt: 2, alignment: { horizontal: :right, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    num_right_joint = styles.add_style(bg_color: joint_bg, num_fmt: 2, alignment: { horizontal: :right, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    num_right_dist = styles.add_style(bg_color: dist_bg, num_fmt: 2, alignment: { horizontal: :right, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    rand_right_mat = styles.add_style(bg_color: mat_bg, alignment: { horizontal: :right, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    rand_right_joint = styles.add_style(bg_color: joint_bg, alignment: { horizontal: :right, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    na_right_mat = styles.add_style(bg_color: mat_bg, i: true, alignment: { horizontal: :right, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)
    na_right_joint = styles.add_style(bg_color: joint_bg, i: true, alignment: { horizontal: :right, vertical: :center }, border: Axlsx::STYLE_THIN_BORDER)

    has_adjusted = locations.any?(&:station_adjusted)
    buffer_ft = @core_generation.lane_start_buffer_ft

    workbook.add_worksheet(name: "Core Locations") do |sheet|
      sheet.add_row(
        ["Mark", "Type", "Sublot", "Lane", "Lot Dist (ft)", "Sublot Station (ft)", "Lane Station (ft)", "Offset in Lane (ft)", "Random (A)", "Random (B)"],
        style: Array.new(10, header_style), height: 20
      )

      locations.each do |loc|
        is_joint = loc.joint?

        lane_value = if is_joint
          left = loc.left_lane&.position || loc.left_lane_id
          right = loc.right_lane&.position || loc.right_lane_id
          (left.present? && right.present?) ? "lanes #{left}/#{right}" : "lanes"
        else
          loc.lane_index
        end

        rand_a_val = loc.station_random_number.present? ? format("%.4f", loc.station_random_number.to_f) : "N/A"
        rand_b_val = loc.offset_random_number.present? ? format("%.4f", loc.offset_random_number.to_f) : "N/A"

        sublot_station = loc.sublot_station_ft || loc.linear_in_sublot_ft

        row = [loc.mark, loc.core_type, loc.asphalt_sublot&.position, lane_value,
               loc.distance_from_lot_start_ft, sublot_station,
               loc.station_in_lane_ft, loc.offset_in_lane_ft, rand_a_val, rand_b_val]

        text_bg = is_joint ? text_left_joint : text_left_mat
        mark_bg = is_joint ? text_left_joint_bold : text_left_mat_bold
        num_bg = is_joint ? num_right_joint : num_right_mat
        rand_bg = is_joint ? rand_right_joint : rand_right_mat

        row_styles = [
          mark_bg, text_bg, text_bg, text_bg,
          num_right_dist, num_right_dist, num_bg, num_bg,
          (rand_a_val == "N/A" ? (is_joint ? na_right_joint : na_right_mat) : rand_bg),
          (rand_b_val == "N/A" ? (is_joint ? na_right_joint : na_right_mat) : rand_bg)
        ]

        sheet.add_row(row, style: row_styles, height: 20)
      end

      20.times { sheet.add_row(Array.new(10, nil)) }

      if has_adjusted
        sheet.add_row(["* adjusted +#{buffer_ft.to_f.round(1)}ft to account for field conditions"])
      end

      if sheet.respond_to?(:sheet_view) && sheet.sheet_view.respond_to?(:pane)
        sheet.sheet_view.pane do |pane|
          pane.state = :frozen
          pane.y_split = 1
          pane.top_left_cell = "A2"
          pane.active_pane = :bottom_left
        end
      end
      sheet.column_widths 18, 10, 8, 16, 14, 18, 20, 18, 12, 12

      [4, 5].each do |idx|
        col = sheet.column_info[idx]
        col.hidden = true if col
      end
    end

    { stream: package.to_stream, filename: xlsx_filename(sublot_positions) }
  end

  private

  def xlsx_filename(sublot_positions)
    range = if sublot_positions.present?
      min, max = sublot_positions.minmax
      min == max ? min.to_s : "#{min}-#{max}"
    else
      ""
    end

    date_str = Time.zone.today.strftime("%m-%d-%Y")
    base = "#{@lot.mix_type}_CORES_#{@lot.lot_number}"
    base += "_Sub_#{range}" if range.present?
    base += "_#{date_str}.xlsx"
    base.tr("/\\:", "---").gsub(" ", "_")
  end
end
