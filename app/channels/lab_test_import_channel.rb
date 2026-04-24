class LabTestImportChannel < ApplicationCable::Channel
  def subscribed
    import = LabTestImport.find_by(id: params[:import_id])

    if import && import.project.present? && import.user_id == current_user&.id
      stream_from "lab_test_import:#{import.id}"
    else
      reject
    end
  end

  def unsubscribed
  end
end
