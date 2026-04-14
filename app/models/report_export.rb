class ReportExport < ApplicationRecord
  belongs_to :report
  belongs_to :user
  
  has_one_attached :file
  
  # Status values: queued, running, completed, failed
  validates :status, presence: true, inclusion: { in: %w[queued running completed failed] }
  validates :progress, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  ERROR_FLAG_RULES = {
    template_missing: /template not found|inspection_template\.docx|faa_weekly_template\.docx/i,
    python_runtime_error: /python|traceback|docxtpl|jinja|open3|subprocess/i,
    image_processing_error: /image|photo|inlineimage|caption/i,
    data_serialization_error: /json|encode|decode|serialization/i,
    filesystem_error: /permission denied|no such file|disk|storage|temp/i,
    timeout_or_resource_error: /timeout|timed out|killed|out of memory|oom/i
  }.freeze
  
  def broadcast_progress(progress_value, message = nil)
    update!(progress: progress_value)
    ActionCable.server.broadcast(
      "report_export:#{id}",
      {
        export_id: id,
        progress: progress_value,
        status: status,
        message: message
      }
    )
  end
  
  def mark_completed!
    update!(status: 'completed', progress: 100)
    broadcast_progress(100, 'Export completed')
  end
  
  def mark_failed!(error, stage: nil)
    formatted_error = self.class.format_error_with_stage(error, stage)
    flags = self.class.flags_for_error(error)

    update!(status: 'failed', error_message: formatted_error)
    ActionCable.server.broadcast(
      "report_export:#{id}",
      {
        export_id: id,
        status: 'failed',
        error: formatted_error,
        error_stage: stage,
        error_flags: flags
      }
    )
  end

  def failure_flags
    return [] unless status == 'failed'

    self.class.flags_for_error(error_message)
  end

  def failure_stage
    self.class.stage_from_error_message(error_message)
  end

  def self.flags_for_error(error)
    message = error.to_s
    return ['unknown_failure'] if message.blank?

    flags = ERROR_FLAG_RULES.each_with_object([]) do |(flag, regex), found|
      found << flag.to_s if regex.match?(message)
    end

    flags << 'unknown_failure' if flags.empty?
    flags
  end

  def self.format_error_with_stage(error, stage)
    base = error.to_s
    return base if stage.blank?
    "[#{stage}] #{base}"
  end

  def self.stage_from_error_message(message)
    match = message.to_s.match(/^\[(?<stage>[^\]]+)\]/)
    match&.[](:stage)
  end
end
