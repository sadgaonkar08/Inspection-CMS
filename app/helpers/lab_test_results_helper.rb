module LabTestResultsHelper
  def spec_partial_key(spec_code)
    case spec_code
    when "P-401" then "p401_hma"
    when "P-403" then "p403_cores"
    when "P-610" then "p610_concrete"
    else "generic"
    end
  end

  # Picks the column-layout partial based on the actual row shape, not just
  # spec_code — P-401 lots may carry both HMA air-voids rows and cores
  # compaction rows. Returns one of: "p401_hma", "p403_cores", "p610_concrete",
  # "generic".
  def result_view_key(result)
    data = result.data || {}
    case result.spec_code
    when "P-401"
      data["core_id"].present? ? "p403_cores" : "p401_hma"
    when "P-403" then "p403_cores"
    when "P-610" then "p610_concrete"
    else "generic"
    end
  end

  def result_view_label(spec_code, view_key)
    case [spec_code, view_key]
    in ["P-401", "p403_cores"] then "P-401 — Compaction Cores"
    in ["P-401", "p401_hma"]   then "P-401 — Mix Properties"
    else spec_code
    end
  end

  def result_badge_class(result)
    case result.to_s
    when "pass" then "success"
    when "fail" then "danger"
    else "secondary"
    end
  end

  def result_label(result)
    case result.to_s
    when "pass" then "PASS"
    when "fail" then "FAIL"
    else "PENDING"
    end
  end
end
