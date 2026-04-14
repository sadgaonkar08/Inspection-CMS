require 'csv'
require 'tempfile'
require 'fileutils'

class ReportsController < ApplicationController
  include Pagy::Backend

  SHOW_SECTIONS = %w[
    checklists
    qa_entries
    core_locations
    workforce_equipment
    quantities
    attachments
    audit_log
  ].freeze
  
  before_action :set_report, only: %i[ show show_section start_export ai_payload ]
  before_action :set_report_for_editing, only: %i[ edit update submit_for_qc ]
  before_action :set_report_for_destroy, only: %i[ destroy ]
  before_action :set_report_for_ai_generation, only: %i[ generate_work_summary generate_commentary ai_status ]
  before_action :set_report_for_qc, only: %i[ approve request_revision ]

  def import
  end

  def import_docx
    uploaded = params[:docx]
    unless uploaded.respond_to?(:path)
      redirect_to import_reports_path, alert: "Please choose a .docx file to import."
      return
    end

    imported_report = current_user.imported_reports.create!(status: :imported)
    imported_report.source_docx.attach(uploaded)

    begin
      parsed = PythonDocxImporter.parse(uploaded.path)
      extracted = parsed.fetch('extracted', {})

      imported_report.update!(
        contract_number: extracted['contract_number'].presence,
        project_title: extracted['project_title'].presence,
        template_confidence: parsed['confidence'],
        template_errors: Array(parsed['errors']).join("\n"),
        parsed_data: parsed
      )

      # Attach extracted photos (1..6) as ActiveStorage attachments
      Array(extracted['photos']).each do |photo|
        path = photo['path']
        next unless path.present? && File.exist?(path)

        imported_report.photos.attach(
          io: File.open(path, 'rb'),
          filename: photo['filename'].presence || File.basename(path),
          content_type: photo['content_type'].presence
        )
      end

      extract_dir = parsed['extract_dir']
      FileUtils.remove_entry(extract_dir) if extract_dir.present? && Dir.exist?(extract_dir)

      if parsed['valid_template'] == false
        imported_report.update!(status: :needs_review)
        redirect_to reports_path(tab: 'imported'), alert: "Imported, but template match is low. Review before using."
      else
        redirect_to reports_path(tab: 'imported'), notice: "DOCX imported successfully."
      end
    rescue => e
      imported_report.update!(status: :needs_review, template_errors: [imported_report.template_errors, e.message].compact.join("\n"))
      redirect_to reports_path(tab: 'imported'), alert: "Import failed: #{e.message}"
    end
  end

  def index
    params[:tab] ||= 'reports'

    if params[:project_id].blank?
      default_project = Project.order(created_at: :desc).first
      params[:project_id] = default_project.id if default_project
    end

    if params[:tab] == 'reports' && params[:status].blank?
      params[:status] = 'in_progress'
    end

    @has_revise_reports = current_user.reports.where(status: :revise).exists?

    if params[:tab] == 'imported'
      @imported_reports = imported_reports_index_scope
      @imported_reports = @imported_reports.includes(:user, :project)
      @imported_reports = @imported_reports.where(project_id: params[:project_id]) if params[:project_id].present?
      @imported_reports = @imported_reports.order(created_at: :desc)
      @pagy_imported, @imported_reports = pagy(@imported_reports)
      respond_to do |format|
        format.html
      end
      return
    end

    if params[:tab] == 'data'
      redirect_to data_view_reports_path(params.permit(:project_id))
      return
    end

    @reports = reports_index_scope

    @reports = @reports.includes(:user, :project, :phase, placed_quantities: :bid_item)

    @reports = @reports.where(status: params[:status]) unless params[:status] == 'all'

    if current_user.can_qc? && params[:status] == 'review'
      @reports = @reports.where.not(user_id: current_user.id)
    end

    apply_search_filters
    
    # Order by relevance if searching, otherwise by date
    if params[:search_text].present?
      @reports = @reports.order(Arel.sql('search_rank DESC NULLS LAST, start_date DESC'))
    else
      @reports = @reports.order(start_date: :desc)
    end
    
    # Paginate results
    @pagy, @reports = pagy(@reports)

    respond_to do |format|
      format.html
      format.csv { stream_csv(@reports) }
    end
  end

  def show
  end

  def show_section
    section = params[:section].to_s
    unless SHOW_SECTIONS.include?(section)
      head :not_found
      return
    end

    @core_locations = core_locations_for_report if section == "core_locations"
    @section_partial = "reports/show_sections/#{section}"
    @section_frame_id = "report_section_#{section}"
    render :show_section, layout: false
  end

  def data_view
    build_data_view
  end

  def copy_candidates
    if params[:project_id].blank? || params[:inspector_id].blank? || params[:date].blank?
      render json: { reports: [] }
      return
    end

    selected_date = parse_date_param(params[:date])
    if selected_date.blank?
      render json: { reports: [] }
      return
    end

    reports = copy_source_scope
                .where(project_id: params[:project_id], user_id: params[:inspector_id], start_date: selected_date)
                .includes(:user, :phase)
                .order(start_date: :desc, created_at: :desc)
                .limit(100)

    render json: {
      reports: reports.map do |report|
        {
          id: report.id,
          label: [
            report.dir_number.presence || "IDR ##{report.id}",
            report.start_date&.strftime("%Y-%m-%d"),
            report.phase&.name,
            report.user&.email
          ].compact.join(" • ")
        }
      end
    }
  end

  def new
    @report = current_user.reports.build(status: :in_progress)
    @inspectors = User.inspector.order(:email)
    
    if params[:project_id].present?
      @project = Project.find_by(id: params[:project_id])
      
      if @project
        @report.project = @project
        
        @report.contractor = @project.prime_contractor if @project.prime_contractor.present?
      end
    end

    if params[:copy_from_report_id].present?
      source_report = copy_source_scope.find_by(id: params[:copy_from_report_id], project_id: @report.project_id)
      build_copy_prefill!(@report, source_report) if source_report
    end

    @report.placed_quantities.build if @report.placed_quantities.empty?
    @report.equipment_entries.build if @report.equipment_entries.empty?
    @report.crew_entries.build if @report.crew_entries.empty?
    
  end

  def edit
    @report.placed_quantities.build if @report.placed_quantities.empty?
    @report.equipment_entries.build if @report.equipment_entries.empty?
    @report.crew_entries.build if @report.crew_entries.empty?
  end

  def create
    @report = current_user.reports.build(report_params)
    @report.status = :in_progress

    if @report.save
      redirect_to report_url(@report), notice: "Report was successfully created."
    else
      @project = @report.project 
      @inspectors = User.inspector.order(:email)

      # Ensure nested sections render with at least one row on validation errors.
      @report.placed_quantities.build if @report.placed_quantities.empty?
      @report.equipment_entries.build if @report.equipment_entries.empty?
      @report.crew_entries.build if @report.crew_entries.empty?

      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @report.update(report_params)
      redirect_to report_url(@report), notice: "Report was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user == @report.user || current_user.admin?
      redirect_to @report, alert: "You are not authorized to delete this report."
      return
    end

    @report.destroy!
    redirect_to reports_url, notice: "Report was successfully deleted."
  end


  def submit_for_qc
    unless @report.in_progress? || @report.revise?
      redirect_to @report, alert: "This report can't be submitted from its current status."
      return
    end

    ActiveRecord::Base.transaction do
      @report.update!(status: :review)
      @report.audit_logs.create!(user: current_user, note: "Report submitted for review")
    end

    redirect_to reports_path, notice: "Report submitted for review."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @report, alert: e.record.errors.full_messages.to_sentence
  end

  def approve
    unless @report.review?
      redirect_to @report, alert: "Only reports in Review can be approved."
      return
    end

    ActiveRecord::Base.transaction do
      @report.update!(status: :finalize, result: :pass)
      @report.audit_logs.create!(user: current_user, note: "Report approved and finalized")
    end

    redirect_to @report, notice: "Report approved and finalized."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @report, alert: e.record.errors.full_messages.to_sentence
  end

  def request_revision
    unless @report.review?
      redirect_to @report, alert: "Only reports in Review can be returned for revision."
      return
    end

    note = params[:note].to_s.strip
    if note.blank?
      @revision_note = note
      flash.now[:alert] = "A revision note is required."
      render :show, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      @report.update!(status: :revise, result: :fail)
      @report.audit_logs.create!(user: current_user, note: note)
    end

    redirect_to @report, alert: "Report returned for revision."
  rescue ActiveRecord::RecordInvalid => e
    @revision_note = note
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :show, status: :unprocessable_entity
  end

  # Async export with progress tracking
  def start_export
    export = ReportExport.create!(
      report: @report,
      user: current_user,
      status: 'queued',
      progress: 0
    )
    
    # Enqueue background job
    ReportExportJob.perform_later(export.id)
    
    render json: {
      export_id: export.id,
      status: 'queued',
      progress: 0
    }
  end

  # Testing endpoint: returns normalized AI payload JSON
  def ai_payload
    render json: ReportAi::PayloadBuilder.build(@report)
  end

  # AI Generation Endpoints

  # POST /reports/:id/generate_work_summary
  def generate_work_summary
    Rails.logger.info("[ReportsController#generate_work_summary] Request report_id=#{@report.id} user_id=#{current_user&.id} current_status=#{@report.ai_status}")

    if @report.ai_generating?
      Rails.logger.warn("[ReportsController#generate_work_summary] Blocked report_id=#{@report.id} user_id=#{current_user&.id} reason=already_generating status=#{@report.ai_status}")
      render json: { error: 'AI generation already in progress' }, status: :conflict
      return
    end

    @report.enqueue_ai_generation!(intent: :work_summary, user: current_user)

    Rails.logger.info("[ReportsController#generate_work_summary] Enqueued report_id=#{@report.id} user_id=#{current_user&.id} new_status=#{@report.reload.ai_status}")

    render json: {
      status: 'queued',
      message: 'Work summary generation started'
    }
  rescue => e
    Rails.logger.error("[ReportsController#generate_work_summary] Error: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /reports/:id/generate_commentary
  def generate_commentary
    Rails.logger.info("[ReportsController#generate_commentary] Request report_id=#{@report.id} user_id=#{current_user&.id} current_status=#{@report.ai_status}")

    if @report.ai_generating?
      Rails.logger.warn("[ReportsController#generate_commentary] Blocked report_id=#{@report.id} user_id=#{current_user&.id} reason=already_generating status=#{@report.ai_status}")
      render json: { error: 'AI generation already in progress' }, status: :conflict
      return
    end

    @report.enqueue_ai_generation!(intent: :commentary, user: current_user)

    Rails.logger.info("[ReportsController#generate_commentary] Enqueued report_id=#{@report.id} user_id=#{current_user&.id} new_status=#{@report.reload.ai_status}")

    render json: {
      status: 'queued',
      message: 'Commentary generation started'
    }
  rescue => e
    Rails.logger.error("[ReportsController#generate_commentary] Error: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /reports/:id/ai_status
  def ai_status
    Rails.logger.debug("[ReportsController#ai_status] report_id=#{@report.id} user_id=#{current_user&.id} status=#{@report.ai_status} has_error=#{@report.ai_error.present?}")

    render json: {
      status: @report.ai_status,
      ai_stage: @report.ai_stage,
      ai_work_summary: @report.ai_work_summary,
      ai_generated_commentary: @report.ai_generated_commentary,
      ai_generated_at: @report.ai_generated_at&.iso8601,
      ai_error: @report.ai_error
    }
  end

  private

    def build_data_view
      project_filter = params[:project_id].presence
      @selected_category = params[:category].presence
      @group_by = params[:group_by].presence || "spec_division"

      @range_start_date = parse_date_param(params[:range_start_date])
      @range_end_date = parse_date_param(params[:range_end_date])

      if @range_start_date.present? && @range_end_date.blank?
        @range_end_date = @range_start_date
      elsif @range_end_date.present? && @range_start_date.blank?
        @range_start_date = @range_end_date
      end

      if @range_start_date.present? && @range_end_date.present? && @range_start_date > @range_end_date
        @range_start_date, @range_end_date = @range_end_date, @range_start_date
      end

      bid_items_scope = BidItem.includes(:project, :spec_item)
      bid_items_scope = bid_items_scope.where(project_id: project_filter) if project_filter
      @bid_item_options = bid_items_scope.order(:code)

      placed_scope = PlacedQuantity.joins(:report)
                                   .where(reports: { status: Report.statuses[:finalize] })
      placed_scope = placed_scope.where(reports: { project_id: project_filter }) if project_filter
      if @range_start_date.present? && @range_end_date.present?
        placed_scope = placed_scope.where(reports: { start_date: @range_start_date..@range_end_date })
      end

      @change_order_filter = params[:change_order_filter].presence
      if @change_order_filter == "original"
        placed_scope = placed_scope.where(change_order_id: nil)
      elsif @change_order_filter == "all_co"
        placed_scope = placed_scope.where.not(change_order_id: nil)
      elsif @change_order_filter.present? && @change_order_filter.match?(/\A\d+\z/)
        placed_scope = placed_scope.where(change_order_id: @change_order_filter)
      end

      @change_order_options = if project_filter
                                ChangeOrder.where(project_id: project_filter).order(:number)
                              else
                                ChangeOrder.none
                              end

      @selected_bid_item = nil
      @selected_bid_item_quantity = nil
      @selected_bid_item_reports_count = 0

      selected_bid_item_id = params[:bid_item_id].presence
      if selected_bid_item_id.present?
        scoped_bid_item = bid_items_scope.find_by(id: selected_bid_item_id)
        if scoped_bid_item
          @selected_bid_item = scoped_bid_item
          selected_scope = placed_scope.where(bid_item_id: scoped_bid_item.id)
          @selected_bid_item_quantity = selected_scope.sum(:quantity).to_f
          @selected_bid_item_reports_count = selected_scope.select(:report_id).distinct.count
        end
      end

      placed_by_bid_item = placed_scope.group(:bid_item_id).sum(:quantity)

      @bid_item_progress = bid_items_scope.order(:code).map do |bid_item|
        placed = placed_by_bid_item[bid_item.id].to_f
        target = bid_item.bid_quantity.to_f if bid_item.bid_quantity.present?
        percent = if target && target.positive?
                    ((placed / target) * 100.0).round(1)
                  else
                    nil
                  end

        {
          bid_item: bid_item,
          placed: placed,
          target: target,
          percent: percent
        }
      end

      category_totals = Hash.new { |hash, key| hash[key] = { placed: 0.0, target: 0.0 } }
      total_target = 0.0
      total_placed = 0.0

      bid_items_scope.find_each do |bid_item|
        target = bid_item.bid_quantity.to_f
        next if target <= 0

        placed = placed_by_bid_item[bid_item.id].to_f
        category = if @group_by == "sov_category"
                     bid_item.sov_category.presence || "Uncategorized"
                   else
                     bid_item.spec_item&.division.presence || "Uncategorized"
                   end

        total_target += target
        total_placed += placed

        category_totals[category][:target] += target
        category_totals[category][:placed] += placed
      end

      @overall_percent = total_target.positive? ? ((total_placed / total_target) * 100.0).round(1) : 0.0

      palette = [
        "#2563eb",
        "#f97316",
        "#10b981",
        "#e11d48",
        "#a855f7",
        "#0ea5e9",
        "#f59e0b",
        "#14b8a6"
      ]

      @category_breakdown = category_totals.map.with_index do |(name, totals), idx|
        percent = totals[:target].positive? ? ((totals[:placed] / totals[:target]) * 100.0).round(1) : 0.0
        contribution = total_target.positive? ? ((totals[:placed] / total_target) * 100.0).round(2) : 0.0

        {
          name: name,
          placed: totals[:placed],
          target: totals[:target],
          percent: percent,
          contribution: contribution,
          color: palette[idx % palette.length]
        }
      end

      @category_options = category_totals.keys.sort

      gradient_for = lambda do |entries|
        start = 0.0
        segments = entries.filter_map do |item|
          next if item[:contribution] <= 0

          finish = start + item[:contribution]
          segment = "#{item[:color]} #{start.round(2)}% #{finish.round(2)}%"
          start = finish
          segment
        end

        segments << "#e5e7eb #{start.round(2)}% 100%" if start < 100.0
        segments.join(", ")
      end

      if @selected_category.present? && category_totals.key?(@selected_category)
        items_for_category = bid_items_scope.select do |bid_item|
          if @group_by == "sov_category"
            (bid_item.sov_category.presence || "Uncategorized") == @selected_category
          else
            (bid_item.spec_item&.division.presence || "Uncategorized") == @selected_category
          end
        end
        category_target = items_for_category.sum { |bid_item| bid_item.bid_quantity.to_f }
        category_placed = items_for_category.sum { |bid_item| placed_by_bid_item[bid_item.id].to_f }

        @item_breakdown = items_for_category.sort_by(&:code).map.with_index do |bid_item, idx|
          target = bid_item.bid_quantity.to_f
          placed = placed_by_bid_item[bid_item.id].to_f
          percent = target.positive? ? ((placed / target) * 100.0).round(1) : 0.0
          contribution = category_target.positive? ? ((placed / category_target) * 100.0).round(2) : 0.0

          {
            name: "#{bid_item.code} — #{bid_item.description}",
            placed: placed,
            target: target,
            percent: percent,
            contribution: contribution,
            color: palette[idx % palette.length]
          }
        end

        @item_breakdown = @item_breakdown.sort_by { |item| -item[:contribution] }
        @chart_percent = category_target.positive? ? ((category_placed / category_target) * 100.0).round(1) : 0.0
        @chart_label = "#{@selected_category} completion"
        @pie_gradient = gradient_for.call(@item_breakdown)
      else
        @selected_category = nil
        @category_breakdown = @category_breakdown.sort_by { |item| -item[:contribution] }
        @chart_percent = @overall_percent
        @chart_label = "Overall completion"
        @pie_gradient = gradient_for.call(@category_breakdown)
      end
    end

    def parse_date_param(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def reports_index_scope
      scope = current_user.can_qc? ? Report.all : current_user.reports
      return scope unless params[:project_id].present?

      scope.where(project_id: params[:project_id])
    end

    def imported_reports_index_scope
      scope = current_user.can_qc? ? ImportedReport.all : current_user.imported_reports
      return scope unless params[:project_id].present?

      scope.where(project_id: params[:project_id])
    end

    def copy_source_scope
      scope = current_user.can_qc? ? Report.all : current_user.reports
      scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?
      scope = scope.where(user_id: params[:inspector_id]) if current_user.can_qc? && params[:inspector_id].present?
      scope
    end

    def build_copy_prefill!(report, source_report)
      copied_attributes = source_report.attributes.except(*copy_excluded_attributes)
      report.assign_attributes(copied_attributes)

      report.assign_attributes(
        placed_quantities_attributes: nested_copy_attributes(source_report.placed_quantities),
        equipment_entries_attributes: nested_copy_attributes(source_report.equipment_entries),
        crew_entries_attributes: nested_copy_attributes(source_report.crew_entries),
        qa_entries_attributes: nested_copy_attributes(source_report.qa_entries),
        checklist_entries_attributes: nested_copy_attributes(source_report.checklist_entries)
      )
    end

    def nested_copy_attributes(records)
      records.map do |record|
        record.attributes.except("id", "report_id", "created_at", "updated_at")
      end
    end

    def copy_excluded_attributes
      %w[
        id
        user_id
        dir_number
        status
        result
        created_at
        updated_at
        approved_by_id
        approved_at
        authorized_by_id
        authorized_date
        ai_status
        ai_generated_at
        ai_error
        searchable_tsvector
        start_date
        end_date
        commentary
        additional_activities
        additional_info
        temp_1
        temp_2
        temp_3
        wind_1
        wind_2
        wind_3
        precip_1
        precip_2
        precip_3
        weather_summary_1
        weather_summary_2
        weather_summary_3
        visibility_1
        visibility_2
        visibility_3
        surface_conditions
        notable_weather_events
      ]
    end

    def set_report
      scope = current_user.can_qc? ? Report.all : current_user.reports

      if action_name == 'show'
        scope = scope.includes(:project, :phase, :user)
      elsif action_name == 'show_section'
        scope = scope.includes(
          *section_includes(params[:section])
        )
      end

      @report = scope.find(params[:id])
    end

    def section_includes(section)
      case section.to_s
      when "checklists"
        [{ checklist_entries: :spec_item }]
      when "qa_entries"
        [:qa_entries]
      when "core_locations"
        [{ core_generations: [:asphalt_lot, { core_locations: [:asphalt_sublot, :asphalt_lane] }] }]
      when "workforce_equipment"
        [:crew_entries, :equipment_entries]
      when "quantities"
        [{ placed_quantities: :bid_item }]
      when "attachments"
        [{ report_attachments: { file_attachment: :blob } }]
      when "audit_log"
        [{ audit_logs: :user }]
      else
        []
      end
    end

    def core_locations_for_report
      @report.core_generations
             .flat_map(&:core_locations)
             .sort_by { |location| location.mark.to_s }
    end

    def set_report_for_destroy
      @report = Report.find(params[:id])
    end

    def set_report_for_editing
      @report = current_user.reports.find(params[:id])

      return if @report.in_progress? || @report.revise?

      redirect_to @report, alert: "This report can't be edited in its current status."
      return
    end

    # AI generation is owner-only and status-gated (same as editing)
    def set_report_for_ai_generation
      @report = current_user.reports.find(params[:id])

      unless @report.ai_generation_allowed_by?(current_user)
        render json: { error: "AI generation not allowed for this report" }, status: :forbidden
        return
      end
    end

    def set_report_for_qc
      unless current_user.can_qc?
        raise ActiveRecord::RecordNotFound
      end

      @report = Report.find(params[:id])

      if @report.user_id == current_user.id
        raise ActiveRecord::RecordNotFound
      end
    end

    def apply_search_filters
      @reports = @reports.filter_by_inspector(params[:inspector]) if params[:inspector].present?
      @reports = @reports.filter_by_text(params[:search_text]) if params[:search_text].present?
      @reports = @reports.filter_by_project(params[:project_id]) if params[:project_id].present?

      @reports = @reports.filter_by_phase(params[:phase_id]) if params[:phase_id].present?
      @reports = @reports.filter_by_has_quantities(params[:has_quantities]) if params[:has_quantities].present?

      @reports = @reports.filter_by_spec_division(params[:spec_division]) if params[:spec_division].present?
      @reports = @reports.filter_by_spec_item(params[:spec_item_id]) if params[:spec_item_id].present?

      @reports = @reports.filter_by_bid_item(params[:bid_item_id]) if params[:bid_item_id].present?

      if params[:precip_min].present?
         max = params[:precip_max].presence || 100 
         @reports = @reports.filter_by_precip_range(params[:precip_min], max)
      end

      if params[:start_date].present?
        end_date = params[:end_date].presence || params[:start_date]
        @reports = @reports.filter_by_date_range(params[:start_date], end_date) 
      end

      if params[:result].present?
        if params[:result] == 'pending'
          @reports = @reports.where(result: [nil, Report.results[:pending]])
        else
          @reports = @reports.where(result: params[:result])
        end
      end
    end

    def stream_csv(reports)
      filename = "Project_Master_Log_#{Date.today}.csv"
      response.headers['Content-Type'] = 'text/csv; charset=utf-8'
      response.headers['Content-Disposition'] = %(attachment; filename="#{filename}")
      response.headers['Cache-Control'] = 'no-cache'
      self.response_body = generate_csv_enumerator(reports)
    end

    def generate_csv_enumerator(reports)
      Enumerator.new do |yielder|
        yielder << CSV.generate_line([
          'IDR #', 'Start Date', 'End Date', 'Inspector', 'Project', 'Phase', 'Status',
          'Shift', 'Temps (1/2/3)', 'Winds (1/2/3)', 'Contractor',
          'Item Code', 'Item Description', 'Quantity', 'Unit', 'Location', 'Notes'
        ])

        reports.each do |report|
          inspector_name = report.user&.email || 'Unknown'
          temps = [report.temp_1, report.temp_2, report.temp_3].compact.join('/')
          winds = [report.wind_1, report.wind_2, report.wind_3].compact.join('/')

          if report.placed_quantities.empty?
            yielder << CSV.generate_line([
              report.dir_number, report.start_date, report.end_date, inspector_name, report.project&.name, report.phase&.name, report.status_label,
              "#{report.shift_start}-#{report.shift_end}", temps, winds, report.contractor,
              '---', 'No Activity', 0, '---', '---', report.commentary
            ])
            next
          end

          report.placed_quantities.each do |entry|
            yielder << CSV.generate_line([
              report.dir_number, report.start_date, report.end_date, inspector_name, report.project&.name, report.phase&.name, report.status_label,
              "#{report.shift_start}-#{report.shift_end}", temps, winds, report.contractor,
              entry.bid_item&.code, entry.bid_item&.description, entry.quantity, entry.bid_item&.unit, entry.location, entry.notes
            ])
          end
        end
      end
    end

    def report_params
      permitted = params.require(:report).permit(
        :start_date, :end_date,
        :dir_number, :project_id, :phase_id, 
        :shift_start, :shift_end,
        :contract_day,
        :contractor,
        :prime_contractor,

        :temp_1, :temp_2, :temp_3,
        :wind_1, :wind_2, :wind_3,
        :precip_1, :precip_2, :precip_3,
        :weather_summary_1, :weather_summary_2, :weather_summary_3,
        :weather, :temperature,
        :visibility_1, :visibility_2, :visibility_3,
        :surface_conditions,
        :notable_weather_events,

        :station_start, :station_end, :plan_sheet, :relevant_docs,
        
        :deficiency_status, :deficiency_desc,
        :safety_incident, :safety_desc,
        :commentary,
        :traffic_control, :traffic_control_note,
        :environmental, :environmental_note,
        :security, :security_note,
        :air_ops_coordination, :air_ops_note,
        :swppp_controls, :swppp_note,
        :phasing_compliance, :phasing_compliance_note,

        :additional_activities, :additional_info,
        
        # AI generated fields (editable by inspector)
        :ai_work_summary, :ai_generated_commentary,
        
        report_attachments_attributes: [:id, :caption, :file, :_destroy],

        crew_entries_attributes: [
          :id, :contractor,
          :superintendent_count, :foreman_count,
          :survey_count, :operator_count, :laborer_count, :electrician_count, 
          :notes, :_destroy
        ],
        equipment_entries_attributes: [
          :id, :make_model, :hours, :quantity, :contractor, :_destroy
        ],
        placed_quantities_attributes: [
          :id, :bid_item_id, :quantity, :location, :notes, :change_order_id, :_destroy,
          :checklist_answers
        ],
        
        checklist_entries_attributes: [:id, :spec_item_id, :_destroy, checklist_answers: {}],

        qa_entries_attributes: [
          :id, :qa_type, :location, :result, :remarks, :_destroy
        ],

        core_generation_ids: []
      )

      if permitted.key?(:core_generation_ids)
        target_project_id = permitted[:project_id].presence || @report&.project_id
        permitted[:core_generation_ids] = scoped_core_generation_ids(permitted[:core_generation_ids], target_project_id)
      end

      permitted
    end

    def scoped_core_generation_ids(raw_ids, project_id)
      ids = Array(raw_ids).map(&:to_i).reject(&:zero?)
      return [] if ids.empty? || project_id.blank?

      CoreGeneration.joins(:asphalt_lot)
                    .where(id: ids, asphalt_lots: { project_id: project_id })
                    .pluck(:id)
    end
end
