class PwlCalculation < ApplicationRecord
  belongs_to :asphalt_lot

  CRITERIA_PWL = "pwl".freeze
  CRITERIA_AVERAGE_THRESHOLD = "average_threshold".freeze

  validates :parameter, presence: true, uniqueness: { scope: :asphalt_lot_id }
  validates :status, presence: true

  def self.upsert_from_result(asphalt_lot, parameter, result, sample_values:)
    record = find_or_initialize_by(asphalt_lot_id: asphalt_lot.id, parameter: parameter)
    record.assign_attributes(
      criteria_type: CRITERIA_PWL,
      n: result.n,
      sample_values: sample_values,
      mean: result.mean,
      std_dev: result.std_dev,
      lower_limit: result.lower_limit,
      upper_limit: result.upper_limit,
      q_lower: result.q_lower,
      q_upper: result.q_upper,
      p_lower: result.p_lower,
      p_upper: result.p_upper,
      pwl_percentage: result.pwl_percentage,
      passed: nil,
      status: result.status.to_s,
      calculated_at: Time.current
    )
    record.save!
    record
  end

  def self.upsert_average_threshold(asphalt_lot, parameter, sample_values:, lower_limit: nil, upper_limit: nil)
    record = find_or_initialize_by(asphalt_lot_id: asphalt_lot.id, parameter: parameter)
    n = sample_values.size
    mean = n.zero? ? nil : sample_values.sum.to_f / n

    passed =
      if mean.nil?
        nil
      else
        ge_lower = lower_limit.nil? || mean >= lower_limit
        le_upper = upper_limit.nil? || mean <= upper_limit
        ge_lower && le_upper
      end

    record.assign_attributes(
      criteria_type: CRITERIA_AVERAGE_THRESHOLD,
      n: n,
      sample_values: sample_values,
      mean: mean,
      std_dev: nil,
      lower_limit: lower_limit,
      upper_limit: upper_limit,
      q_lower: nil,
      q_upper: nil,
      p_lower: nil,
      p_upper: nil,
      pwl_percentage: nil,
      passed: passed,
      status: n.zero? ? "no_data" : "ok",
      calculated_at: Time.current
    )
    record.save!
    record
  end
end
