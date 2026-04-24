require "csv"

module Api
  module V1
    class LabTestResultsController < Api::BaseController
      before_action :set_project
      before_action :set_result, only: %i[show update destroy]

      # GET /api/v1/projects/:project_id/lab_test_results
      def index
        results = filtered_results
                    .includes(:asphalt_lot, :report)
                    .order(test_date: :desc, id: :desc)
                    .limit(params[:limit] || 100)

        render json: results.map { |r| result_payload(r) }
      end

      # GET /api/v1/projects/:project_id/lab_test_results/:id
      def show
        render json: result_payload(@result)
      end

      # PATCH /api/v1/projects/:project_id/lab_test_results/:id
      def update
        if @result.update(result_params)
          render json: result_payload(@result)
        else
          render json: { errors: @result.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/projects/:project_id/lab_test_results/:id
      def destroy
        @result.destroy!
        head :no_content
      end

      # GET /api/v1/projects/:project_id/lab_test_results/export_csv
      def export_csv
        spec = params[:spec_code].presence
        unless %w[P-401 P-403].include?(spec)
          return render json: { error: "CSV export is available for P-401 and P-403. Use export_xlsx for P-610." }, status: :unprocessable_entity
        end

        results = @project.lab_test_results
                          .includes(:asphalt_lot, :report)
                          .by_spec_code(spec)
                          .order(test_date: :desc, id: :desc)

        csv_string = CSV.generate do |csv|
          csv << csv_headers_for(spec)
          results.each { |r| csv << csv_row_for(spec, r) }
        end

        send_data csv_string,
                  filename: "lab_test_results_#{spec.downcase}_#{Date.current.iso8601}.csv",
                  type: "text/csv"
      end

      # GET /api/v1/projects/:project_id/lab_test_results/export_xlsx
      def export_xlsx
        spec = params[:spec_code].presence
        unless spec == "P-610"
          return render json: { error: "XLSX export is only available for P-610 results." }, status: :unprocessable_entity
        end

        results = @project.lab_test_results
                          .by_spec_code("P-610")
                          .order(test_date: :desc, id: :desc)

        package = P610QaqcXlsxExporter.new(results).build

        send_data package.to_stream.read,
                  filename: "p610_qaqc_summary_#{Date.current.iso8601}.xlsx",
                  type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      end

      private

      def set_project
        @project = Project.find(params[:project_id])
      end

      def set_result
        @result = @project.lab_test_results.find(params[:id])
      end

      def result_params
        params.require(:lab_test_result).permit(:sublot_number, :result, :notes, :test_date, :hes)
      end

      def filtered_results
        @project.lab_test_results
                .by_spec_code(params[:spec_code].presence)
                .by_result(params[:result].presence)
                .by_date_range(parse_date(params[:date_from]), parse_date(params[:date_to]))
      end

      def parse_date(value)
        return nil if value.blank?
        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def result_payload(r)
        {
          id: r.id,
          project_id: r.project_id,
          lab_test_import_id: r.lab_test_import_id,
          spec_code: r.spec_code,
          lab_name: r.lab_name,
          report_date: r.report_date,
          test_date: r.test_date,
          sublot_number: r.sublot_number,
          result: r.result,
          notes: r.notes,
          data: r.data,
          asphalt_lot_id: r.asphalt_lot_id,
          asphalt_lot_number: r.asphalt_lot&.lot_number,
          report_id: r.report_id,
          report_dir_number: r.report&.dir_number,
          hes: r.hes,
          created_by: r.created_by&.full_name,
          created_at: r.created_at
        }
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
        end
      end

      def csv_row_for(spec_code, result)
        d = result.data || {}
        lot_label = result.asphalt_lot&.lot_number
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
        end
      end
    end
  end
end
