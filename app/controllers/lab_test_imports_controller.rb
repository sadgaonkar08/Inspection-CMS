class LabTestImportsController < ApplicationController
  before_action :set_project
  before_action :set_import, only: %i[show destroy approve reject]

  def new
    @import = @project.lab_test_imports.build
    @asphalt_lots = @project.asphalt_lots.order(:lot_number)
    @reports = @project.reports.order(start_date: :desc).limit(200)
  end

  def create
    @import = @project.lab_test_imports.build(import_params.merge(user: current_user, status: "pending"))

    if @import.save
      LabTestExtractionJob.perform_later(@import.id)
      redirect_to project_lab_test_import_path(@project, @import)
    else
      @asphalt_lots = @project.asphalt_lots.order(:lot_number)
      @reports = @project.reports.order(start_date: :desc).limit(200)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: status_payload(@import) }
    end
  end

  def destroy
    @import.destroy!
    redirect_to project_lab_test_results_path(@project), notice: "Import deleted.", status: :see_other
  end

  def approve
    if @import.needs_review?
      ActiveRecord::Base.transaction do
        persist_results_from_parsed_data!(@import)
        @import.update!(status: "saved")
      end
      @import.lab_test_results.distinct.pluck(:asphalt_lot_id).compact.each do |lot_id|
        PwlRecalculationJob.perform_later(lot_id)
      end
      redirect_to project_lab_test_import_path(@project, @import), notice: "Import approved."
    else
      redirect_to project_lab_test_import_path(@project, @import), alert: "Only imports needing review can be approved."
    end
  end

  def reject
    @import.update!(status: "rejected")
    redirect_to project_lab_test_import_path(@project, @import), notice: "Import rejected."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_import
    @import = @project.lab_test_imports.find(params[:id])
  end

  def import_params
    params.require(:lab_test_import).permit(:spec_code, :source_pdf, :asphalt_lot_id, :report_id)
  end

  def status_payload(import)
    {
      id: import.id,
      status: import.status,
      row_count: import.row_count,
      lab_name: import.lab_name,
      errors: import.extraction_errors
    }
  end

  def persist_results_from_parsed_data!(import)
    rows = Array(import.parsed_data)
    header = import.report_header || {}
    lot_resolver = LabTestLotResolver.new(import.project)

    rows.each do |row|
      resolved_lot_id = lot_resolver.resolve(row["sublot_number"]) || import.asphalt_lot_id

      import.lab_test_results.create!(
        project_id:     import.project_id,
        asphalt_lot_id: resolved_lot_id,
        report_id:      import.report_id,
        spec_code:      import.spec_code,
        lab_name:       header["lab_name"] || import.lab_name,
        report_date:    parse_date(header["report_date"]),
        test_date:      parse_date(row["test_date"]) || parse_date(header["report_date"]),
        sublot_number:  row["sublot_number"],
        result:         row["result"],
        data:           row,
        created_by_id:  current_user&.id
      )
    end
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
