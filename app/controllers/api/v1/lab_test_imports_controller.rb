module Api
  module V1
    class LabTestImportsController < Api::BaseController
      before_action :set_project
      before_action :set_import, only: %i[show destroy approve reject]

      # GET /api/v1/projects/:project_id/lab_test_imports
      def index
        scope = @project.lab_test_imports.order(created_at: :desc)
        scope = scope.where(spec_code: params[:spec_code]) if params[:spec_code].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.limit(params[:limit] || 50)

        render json: scope.map { |i| import_summary(i) }
      end

      # GET /api/v1/projects/:project_id/lab_test_imports/:id
      def show
        render json: import_detail(@import)
      end

      # POST /api/v1/projects/:project_id/lab_test_imports
      def create
        @import = @project.lab_test_imports.build(
          import_params.merge(user: current_user, status: "pending")
        )

        if @import.save
          LabTestExtractionJob.perform_later(@import.id)
          render json: import_detail(@import), status: :accepted
        else
          render json: { errors: @import.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/projects/:project_id/lab_test_imports/:id
      def destroy
        @import.destroy!
        head :no_content
      end

      # PATCH /api/v1/projects/:project_id/lab_test_imports/:id/approve
      def approve
        unless @import.needs_review?
          return render json: { error: "Only imports in needs_review can be approved (current: #{@import.status})" },
                        status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          persist_results_from_parsed_data!(@import)
          @import.update!(status: "saved")
        end

        render json: import_detail(@import.reload)
      end

      # PATCH /api/v1/projects/:project_id/lab_test_imports/:id/reject
      def reject
        @import.update!(status: "rejected")
        render json: import_detail(@import)
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

      def import_summary(import)
        {
          id: import.id,
          project_id: import.project_id,
          spec_code: import.spec_code,
          status: import.status,
          lab_name: import.lab_name,
          row_count: import.row_count,
          asphalt_lot_id: import.asphalt_lot_id,
          report_id: import.report_id,
          uploaded_by: import.user&.full_name,
          created_at: import.created_at
        }
      end

      def import_detail(import)
        import_summary(import).merge(
          report_header: import.report_header,
          parsed_data: import.parsed_data,
          extraction_errors: import.extraction_errors,
          results_count: import.lab_test_results.count
        )
      end

      def persist_results_from_parsed_data!(import)
        rows = Array(import.parsed_data)
        header = import.report_header || {}

        rows.each do |row|
          import.lab_test_results.create!(
            project_id:     import.project_id,
            asphalt_lot_id: import.asphalt_lot_id,
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
  end
end
