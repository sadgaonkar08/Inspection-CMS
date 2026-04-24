module P610Export
  class Serializer
    def initialize(result)
      @result = result
      @data = result.data || {}
    end

    def call
      {
        hes: @result.hes,
        sample_date: parse_date(@data["date_sampled"]),
        qa_lab_id: @data["lab_id_number"],
        qc_lab_id: nil,
        truck_ticket: @data["ticket_number"],
        supplier: @data["supplier"],
        mix_id: @data["mix_number"],
        source_of_sample: nil,
        slump_qa: @data["slump_in"],
        slump_qc: nil,
        air_content_qa: @data["air_content_pct"],
        air_content_qc: nil,
        remark: @result.notes,
        sample_by: nil,
        submittal_number: nil,
        manufacturer: nil,
        design_strength_psi: @data["specified_strength_psi"],
        cylinders: cylinder_rows
      }
    end

    private

    def cylinder_rows
      list = Array(@data["cylinders"]).reject { |c| c["status"] == "held" }
      list.sort_by { |c| [c["age_days"].to_i, c["id"].to_s] }.map do |c|
        {
          label: c["id"],
          age_days: c["age_days"],
          date_tested: parse_date(c["date_tested"]),
          actual_qa_psi: c["ultimate_stress_psi"]
        }
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
