module LabTestImportsHelper
  def report_option_label(report)
    parts = []
    parts << (report.dir_number.presence || "IDR ##{report.id}")
    parts << report.start_date.strftime("%Y-%m-%d") if report.start_date
    parts.join(" — ")
  end

  def status_badge_class(status)
    case status.to_s
    when "saved"        then "success"
    when "needs_review" then "warning"
    when "rejected"     then "danger"
    when "pending"      then "info"
    else "secondary"
    end
  end
end
