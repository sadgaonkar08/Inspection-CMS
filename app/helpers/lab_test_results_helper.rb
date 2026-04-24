module LabTestResultsHelper
  def spec_partial_key(spec_code)
    case spec_code
    when "P-401" then "p401_hma"
    when "P-403" then "p403_cores"
    when "P-610" then "p610_concrete"
    else "generic"
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
