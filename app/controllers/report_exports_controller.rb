class ReportExportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_report_export, only: [:show, :download]
  before_action :authorize_export, only: [:show, :download]

  def show
    render json: {
      id: @export.id,
      status: @export.status,
      progress: @export.progress,
      error: @export.error_message,
      error_flags: @export.failure_flags,
      error_stage: @export.failure_stage,
      download_url: @export.status == 'completed' && @export.file.attached? ? download_report_report_export_path(@export.report, @export) : nil
    }
  end

  def download
    if @export.status == 'completed' && @export.file.attached?
      redirect_to rails_blob_path(@export.file, disposition: "attachment"), allow_other_host: true
    else
      redirect_to @export.report, alert: "Export file is not ready yet."
    end
  end

  private

  def set_report_export
    @export = ReportExport.find(params[:id])
  end

  def authorize_export
    # Only the user who created the export can access it
    unless @export.user_id == current_user.id
      redirect_to reports_path, alert: "You are not authorized to access this export."
    end
  end
end
