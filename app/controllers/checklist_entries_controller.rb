class ChecklistEntriesController < ApplicationController

  def create
    @report = Report.find(params[:report_id])
    @spec = SpecItem.find(params[:spec_item_id])
    
    # Find existing entry or start a new one
    @entry = @report.checklist_entries.find_or_initialize_by(spec_item: @spec)
    
    # Save the answers (passed as a JSON object)
    answers = params.require(:answers)
    answers_hash = answers.respond_to?(:to_unsafe_h) ? answers.to_unsafe_h : answers.to_h
    @entry.checklist_answers = answers_hash
    
    if @entry.save
      render json: {
        status: "success",
        id: @entry.id,
        spec_code: @spec.code,
        spec_desc: @spec.description
      }
    else
      render json: { status: "error", message: @entry.errors.full_messages.join(", ") }, status: 422
    end
  end

  def destroy
    report = Report.find(params[:report_id])
    entry = report.checklist_entries.find(params[:id])
    entry.destroy!
    render json: { status: "success" }
  end
end