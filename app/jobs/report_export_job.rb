class ReportExportJob < ApplicationJob
  queue_as :default

  def perform(export_id)
    stage = 'initialize'
    export = ReportExport.find_by(id: export_id)

    unless export
      Rails.logger.warn("ReportExportJob skipped: export #{export_id} no longer exists")
      return
    end

    report = export.report
    
    begin
      # Update status to running
      stage = 'starting'
      export.update!(status: 'running')
      export.broadcast_progress(5, 'Starting export...')
      
      # Stage 1: Prepare data (20%)
      stage = 'prepare_data'
      export.broadcast_progress(20, 'Preparing report data...')
      
      # Stage 2: Generate document (60%)
      stage = 'generate_document'
      export.broadcast_progress(40, 'Generating Word document...')
      
      # Generate using the Python docxtpl exporter
      temp_file = PythonDocxExporter.generate(report)
      
      # PythonDocxExporter now raises an error if generation fails, so we can assume success here.
      
      # Stage 3: Save file (80%)
      stage = 'save_document'
      export.broadcast_progress(80, 'Saving document...')
      
      # Attach the generated file to the export record
      File.open(temp_file.path, 'rb') do |file|
        export.file.attach(
          io: file,
          filename: report.export_filename,
          content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        )
      end
      
      # Clean up temp file
      temp_file.close
      temp_file.unlink
      
      # Stage 4: Complete (100%)
      stage = 'complete'
      export.mark_completed!
      
    rescue => e
      Rails.logger.error("ReportExportJob failed for export #{export_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      export.mark_failed!(e.message, stage: stage) if export&.persisted?
    end
  end
end
