class PwlRecalculationJob < ApplicationJob
  queue_as :lab_extraction

  # P-401 uses statistical PWL (FAA AC 150/5370-10H). For each parameter:
  # which spec the values come from, the JSONB key holding the per-sublot value,
  # the keys holding the parsed L/U limits, and an optional JSONB-containment
  # filter (e.g. core_type=mat).
  P401_PARAMETERS = {
    "air_voids" => {
      spec_code: "P-401",
      value_key: "air_voids_avg",
      lower_limit_key: "air_voids_min_pct",
      upper_limit_key: "air_voids_max_pct",
      data_filter: nil
    }
  }.freeze

  # P-403 uses simple lot-average vs. fixed FAA item P-403 thresholds.
  # No statistical PWL — we just take the mean of the per-sublot values and
  # check pass/fail. Limits hardcoded to the spec defaults.
  P403_PARAMETERS = {
    "mat_density" => {
      spec_code: "P-403",
      value_key: "compaction_pct",
      data_filter: { "core_type" => "mat" },
      lower_limit: 94.0,
      upper_limit: nil
    },
    "joint_density" => {
      spec_code: "P-403",
      value_key: "compaction_pct",
      data_filter: { "core_type" => "joint" },
      lower_limit: 92.0,
      upper_limit: nil
    },
    "air_voids" => {
      # P-403 air voids may be reported on either spec_code, so we don't filter.
      spec_code: nil,
      value_key: "air_voids_avg",
      data_filter: nil,
      lower_limit: 2.0,
      upper_limit: 5.0
    }
  }.freeze

  def perform(asphalt_lot_id)
    lot = AsphaltLot.find_by(id: asphalt_lot_id)
    return unless lot

    case lot.mix_type
    when "P-403"
      recalculate_p403(lot)
    else
      # Default to P-401 behavior for P-401 and any unrecognized mix_type
      # (preserves prior behavior — calculations only fire when matching data exists).
      recalculate_p401(lot)
    end
  end

  private

  def recalculate_p401(lot)
    P401_PARAMETERS.each do |parameter, source|
      results = source_results(lot, source)
      values = results.map { |r| r.data&.dig(source[:value_key]) }.compact

      if values.empty?
        PwlCalculation.where(asphalt_lot_id: lot.id, parameter: parameter).delete_all
        next
      end

      lower_limit = source[:lower_limit_key] && first_non_nil(results, source[:lower_limit_key])
      upper_limit = source[:upper_limit_key] && first_non_nil(results, source[:upper_limit_key])

      calc_result = PwlCalculator.new(values, lower_limit: lower_limit, upper_limit: upper_limit).call
      PwlCalculation.upsert_from_result(lot, parameter, calc_result, sample_values: values)
    end
  end

  def recalculate_p403(lot)
    P403_PARAMETERS.each do |parameter, source|
      results = source_results(lot, source)
      values = results.map { |r| r.data&.dig(source[:value_key]) }.compact.map(&:to_f)

      if values.empty?
        PwlCalculation.where(asphalt_lot_id: lot.id, parameter: parameter).delete_all
        next
      end

      PwlCalculation.upsert_average_threshold(
        lot,
        parameter,
        sample_values: values,
        lower_limit: source[:lower_limit],
        upper_limit: source[:upper_limit]
      )
    end
  end

  def source_results(lot, source)
    scope = lot.lab_test_results
    scope = scope.where(spec_code: source[:spec_code]) if source[:spec_code]
    if source[:data_filter]
      scope = scope.where("data @> ?::jsonb", source[:data_filter].to_json)
    end
    scope.order(:sublot_number, :id)
  end

  def first_non_nil(results, key)
    results.each do |r|
      v = r.data&.dig(key)
      return v unless v.nil?
    end
    nil
  end
end
