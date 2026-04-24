class Report < ApplicationRecord
  FLEXIBLE_PAVEMENT_CODES = %w[P-401 P-403].freeze

  after_initialize :set_defaults, if: :new_record?
  before_save :calculate_automatic_result, if: :should_calculate_automatic_result?
  after_create :log_creation

  belongs_to :project, optional: true
  belongs_to :phase, optional: true
  belongs_to :user
  belongs_to :authorized_by, class_name: 'User', optional: true
  
  has_many :audit_logs, class_name: 'AuditLog', dependent: :destroy
  has_many :report_core_generations, dependent: :destroy
  has_many :core_generations, through: :report_core_generations

  
  has_many :placed_quantities, dependent: :destroy
  accepts_nested_attributes_for :placed_quantities, 
                                allow_destroy: true, 
                                reject_if: proc { |att| att['bid_item_id'].blank? }

  has_many :equipment_entries, dependent: :destroy
  accepts_nested_attributes_for :equipment_entries, 
                                allow_destroy: true, 
                                reject_if: proc { |att| att['make_model'].blank? && att['contractor'].blank? && att['quantity'].blank? && att['hours'].blank? }

  has_many :crew_entries, dependent: :destroy
  accepts_nested_attributes_for :crew_entries, 
                                allow_destroy: true, 
                                reject_if: proc { |att|
                                  att['contractor'].blank? &&
                                    att['superintendent_count'].blank? &&
                                    att['foreman_count'].blank? &&
                                    att['survey_count'].blank? &&
                                    att['operator_count'].blank? &&
                                    att['laborer_count'].blank? &&
                                    att['electrician_count'].blank? &&
                                    att['notes'].blank?
                                }

  has_many :qa_entries, dependent: :destroy
  accepts_nested_attributes_for :qa_entries, allow_destroy: true, reject_if: :all_blank

  has_many :report_attachments, dependent: :destroy
  accepts_nested_attributes_for :report_attachments, allow_destroy: true

  has_many :checklist_entries, dependent: :destroy
  accepts_nested_attributes_for :checklist_entries,
                                allow_destroy: true,
                                reject_if: :all_blank

  has_many :report_exports, dependent: :destroy
  has_many :lab_test_results, dependent: :nullify

  # Callbacks
  before_validation :set_contract_day_if_blank
  
  # Validations
  validates :start_date, presence: true
  validates :project, presence: true
  validates_associated :placed_quantities
  validate :core_generations_match_project
  
  enum status: { in_progress: 0, review: 1, revise: 2, finalize: 3 }
  enum result: { pending: 0, pass: 1, fail: 2, as_built: 3 }
  
  enum deficiency_status: { no_deficiency: 0, yes_deficiency: 1, cdr: 2, ncr: 3 }
  enum safety_incident:   { safety_no: 0, safety_yes: 1, safety_na: 2 }
  
  # AI generation status values (stored as string, not enum to avoid migration complexity)
  AI_STATUSES = %w[idle queued running success failed].freeze
  
  enum traffic_control:       { tc_na: 0, tc_yes: 1, tc_no: 2 }
  enum environmental:         { env_na: 0, env_yes: 1, env_no: 2 }
  enum security:              { sec_na: 0, sec_yes: 1, sec_no: 2 }
  enum air_ops_coordination:  { air_na: 0, air_yes: 1, air_no: 2 }
  enum swppp_controls:        { swppp_na: 0, swppp_yes: 1, swppp_no: 2 }
  enum phasing_compliance:    { phase_na: 0, phase_yes: 1, phase_no: 2 }

  scope :filter_by_inspector, ->(query) { 
    joins(:user).where("users.email ILIKE ?", "%#{query}%") 
  }
  
  scope :filter_by_project, ->(project_id) { where(project_id: project_id) }
  
  scope :filter_by_bid_item, ->(bid_item_id) {
    joins(:placed_quantities).where(placed_quantities: { bid_item_id: bid_item_id }).distinct
  }

  # Full-text search using PostgreSQL tsvector with relevance ranking
  # Falls back to ILIKE if tsvector column doesn't exist yet (pre-migration)
  scope :filter_by_text, ->(query) {
    if column_names.include?('searchable_tsvector')
      tsquery = sanitize_sql_array(["plainto_tsquery('english', ?)", query])
      where("searchable_tsvector @@ #{tsquery}")
        .select("reports.*, ts_rank(searchable_tsvector, #{tsquery}) AS search_rank")
    else
      # Fallback for pre-migration compatibility
      term = "%#{query}%"
      where(
        "commentary ILIKE ? OR " \
        "additional_activities ILIKE ? OR " \
        "additional_info ILIKE ? OR " \
        "deficiency_desc ILIKE ? OR " \
        "safety_desc ILIKE ? OR " \
        "notable_weather_events ILIKE ?",
        term, term, term, term, term, term
      )
    end
  }

  scope :filter_by_phase, ->(phase_id) { where(phase_id: phase_id) }

  scope :filter_by_has_quantities, ->(value) {
    case value.to_s
    when 'yes'
      joins(:placed_quantities).distinct
    when 'no'
      left_outer_joins(:placed_quantities).where(placed_quantities: { id: nil })
    else
      all
    end
  }

  scope :filter_by_spec_division, ->(division) {
    joins(placed_quantities: { bid_item: :spec_item })
      .where(spec_items: { division: division })
      .distinct
  }

  scope :filter_by_spec_item, ->(spec_item_id) {
    joins(placed_quantities: { bid_item: :spec_item })
      .where(spec_items: { id: spec_item_id })
      .distinct
  }

  scope :filter_by_date_range, ->(start_date, end_date) { 
    where(start_date: start_date..end_date) 
  }

  scope :filter_by_precip_range, ->(min, max) {
    safe_cast = ->(col) { "CASE WHEN #{col} ~ '^[0-9]+(\\.[0-9]+)?$' THEN #{col}::numeric ELSE 0 END" }
    where(
      "(#{safe_cast.call('precip_1')} BETWEEN ? AND ?) OR " \
      "(#{safe_cast.call('precip_2')} BETWEEN ? AND ?) OR " \
      "(#{safe_cast.call('precip_3')} BETWEEN ? AND ?)",
      min, max, min, max, min, max
    )
  }

  
  STATUS_LABELS = {
    in_progress: 'In-progress',
    review: 'Review',
    revise: 'Revise',
    finalize: 'Finalize'
  }.freeze

  def self.status_label(key)
    return nil if key.nil? || (key.respond_to?(:empty?) && key.empty?)

    STATUS_LABELS[key.to_sym] || key.to_s.humanize
  end

  def status_label
    self.class.status_label(status)
  end

  # AI Generation Methods
  
  # Check if AI generation can be triggered (owner-only + status gating)
  def ai_generation_allowed_by?(user)
    return false unless user
    return false unless user_id == user.id
    return false unless in_progress? || revise?
    true
  end

  # Check if AI is currently processing
  def ai_generating?
    ai_status.in?(%w[queued running])
  end

  # Queue AI generation for a specific intent
  def enqueue_ai_generation!(intent:, user:)
    unless ai_generation_allowed_by?(user)
      raise "AI generation not allowed for this report/user combination"
    end

    update_columns(ai_status: 'queued', ai_error: nil)
    ReportAiGenerateJob.perform_later(id, intent.to_s, user.id)
    
    audit_logs.create!(
      user: user,
      note: "AI #{intent.to_s.humanize} generation requested"
    )
  end

  def set_defaults
    self.status ||= :in_progress
    self.result ||= :pending
    
    self.start_date ||= Date.current
    self.end_date ||= self.start_date
    self.shift_start ||= Time.current.strftime("%H:%M")
    
    self.deficiency_status ||= :no_deficiency
    self.safety_incident ||= :safety_no
    self.traffic_control ||= :tc_na
    self.environmental ||= :env_na
    self.security ||= :sec_na
    self.air_ops_coordination ||= :air_na
    self.swppp_controls ||= :swppp_na
    self.phasing_compliance ||= :phase_na
  end

  def search_hits(term)
    return 0 if term.blank?
    
    count = 0
    [commentary, additional_activities, additional_info, deficiency_desc, safety_desc, notable_weather_events].each do |field|
      next if field.blank?
      hits = field.scan(/#{Regexp.escape(term)}/i).count
      count += hits
    end
    count
  end

  def calculate_automatic_result
    if cdr? || ncr? || qa_entries.any?(&:qa_fail?)
      self.result = :fail
      return
    end

    if yes_deficiency? || qa_entries.any?(&:qa_pending?)
      self.result = :pending
      return
    end

    self.result = :pass
  end

  def should_calculate_automatic_result?
    return false unless in_progress? || revise?
    return true if result.blank?

    pending?
  end

  def inspector_name
    user&.full_name || user&.email
  end

  def inspector_initials
    return "" unless user.present?

    user.initials
  end
  
  def export_filename
    # Format: YYYY-MM-DD-CVL IDR-Initials.docx
    # Example: 2025-03-22-CVL IDR-AC.docx
    date_str = start_date.strftime("%Y-%m-%d")
    "#{date_str}-CVL IDR-#{inspector_initials}.docx"
  end

  def flexible_pavement_checklist_saved?
    return false unless persisted?

    checklist_entries
      .joins(:spec_item)
      .where(
        "UPPER(spec_items.division) LIKE :division OR UPPER(spec_items.code) IN (:codes)",
        division: "%FLEXIBLE PAVEMENT%",
        codes: FLEXIBLE_PAVEMENT_CODES
      )
      .exists?
  end

  def core_generations_match_project
    return if project_id.blank? || core_generations.blank?

    invalid_scope = core_generations.joins(:asphalt_lot)
                                  .where.not(asphalt_lots: { project_id: project_id })
    return unless invalid_scope.exists?

    errors.add(:core_generations, "must belong to the same project as the report")
  end

  private :core_generations_match_project
  
  def contract_day_display
    return nil unless project&.contract_start_date && project&.contract_days && start_date
    
    days_since_start = contract_day || calculated_contract_day
    total_days = project.contract_days
    
    "Day #{days_since_start} of #{total_days}"
  end
  
  def calculated_contract_day
    return nil unless project&.contract_start_date && start_date
    (start_date - project.contract_start_date).to_i + 1
  end
  
  private
  
  def set_contract_day_if_blank
    self.contract_day ||= calculated_contract_day
  end

  private

  def log_creation
    audit_logs.create(
      user: user,
      note: "Report created by #{user.email}"
    )
  end
end
