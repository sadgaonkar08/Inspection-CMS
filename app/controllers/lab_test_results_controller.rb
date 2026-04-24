require "csv"

class LabTestResultsController < ApplicationController
  before_action :set_project
  before_action :set_result, only: %i[edit update destroy]

  def index
    @spec_code = params[:spec_code].presence
    @result_filter = params[:result].presence
    @date_from = parse_date(params[:date_from])
    @date_to = parse_date(params[:date_to])

    @results = @project.lab_test_results
                       .includes(:asphalt_lot, :report)
                       .by_spec_code(@spec_code)
                       .by_result(@result_filter)
                       .by_date_range(@date_from, @date_to)
                       .order(test_date: :desc, id: :desc)
  end

  def edit
  end

  def update
    if @result.update(result_params)
      redirect_to project_lab_test_results_path(@project), notice: "Result updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @result.destroy!
    redirect_to project_lab_test_results_path(@project), notice: "Result deleted.", status: :see_other
  end

  def export_csv
    spec = params[:spec_code].presence || "P-401"
    results = @project.lab_test_results.includes(:asphalt_lot, :report).by_spec_code(spec).order(test_date: :desc, id: :desc)

    csv_string = CSV.generate do |csv|
      csv << csv_headers_for(spec)
      results.each { |r| csv << csv_row_for(spec, r) }
    end

    send_data csv_string,
              filename: "lab_test_results_#{spec.downcase}_#{Date.current.iso8601}.csv",
              type: "text/csv"
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_result
    @result = @project.lab_test_results.find(params[:id])
  end

  def result_params
    params.require(:lab_test_result).permit(:sublot_number, :result, :notes, :test_date)
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def csv_headers_for(spec_code)
    case spec_code
    when "P-401"
      ["Report Date", "Test Date", "Lot", "Sublot", "Tonnage Pt (T)", "Time in Oven (hrs)",
       "Gyrations", "Gmb Avg", "Gmm Avg", "Air Voids Avg (%)",
       "Air Voids Min (%)", "Air Voids Max (%)", "Result"]
    when "P-403"
      ["Report Date", "Lot", "Sublot", "Core ID", "Core Type", "Thickness AR (in)",
       "Thickness Trimmed (in)", "Gmb", "Gmm", "Compaction (%)",
       "Required (%)", "ASTM", "Result"]
    when "P-610"
      ["Report Date", "Daily Report", "Lab ID", "Set", "Date Sampled", "Supplier", "Mix #",
       "Cylinders Tested", "Cylinders Total",
       "Avg Strength (psi)", "Avg Age (days)", "Avg Source",
       "Specified (psi)", "Specified Age (days)", "Result"]
    else
      ["Report Date", "Spec", "Lot / Report", "Sublot", "Result"]
    end
  end

  def csv_row_for(spec_code, result)
    d = result.data || {}
    lot_label = result.asphalt_lot&.lot_number
    report_label = result.report&.dir_number.presence || (result.report && "IDR ##{result.report_id}")
    case spec_code
    when "P-401"
      [result.report_date, result.test_date, lot_label, result.sublot_number,
       d["tonnage_point_tons"], d["time_in_oven_hrs"], d["gyrations"],
       d["gmb_avg"], d["gmm_avg"], d["air_voids_avg"],
       d["air_voids_min_pct"], d["air_voids_max_pct"], result.result]
    when "P-403"
      [result.report_date, lot_label, result.sublot_number, d["core_id"], d["core_type"],
       d["thickness_as_received_in"], d["thickness_trimmed_in"],
       d["gmb"], d["gmm"], d["compaction_pct"],
       d["required_compaction_pct"], d["astm_standard"], result.result]
    when "P-610"
      [result.report_date, report_label, d["lab_id_number"], d["set_number"], d["date_sampled"],
       d["supplier"], d["mix_number"],
       d["num_tested"], d["num_cylinders"],
       d["avg_strength_psi"], d["avg_strength_at_days"], d["avg_strength_source"],
       d["specified_strength_psi"], d["specified_at_days"], result.result]
    else
      [result.report_date, result.spec_code, lot_label || report_label, result.sublot_number, result.result]
    end
  end
end
