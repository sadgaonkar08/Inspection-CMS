class LabTestResult < ApplicationRecord
  belongs_to :project
  belongs_to :lab_test_import
  belongs_to :asphalt_lot, optional: true
  belongs_to :report, optional: true
  belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

  enum result: { pass: "pass", fail: "fail" }

  validates :spec_code, presence: true

  scope :by_spec_code,  ->(code)     { where(spec_code: code) if code.present? }
  scope :by_result,     ->(r)        { where(result: r) if r.present? }
  scope :by_asphalt_lot, ->(lot_id)  { where(asphalt_lot_id: lot_id) if lot_id.present? }
  scope :by_date_range, ->(from, to) { where(test_date: from..to) if from.present? && to.present? }
end
