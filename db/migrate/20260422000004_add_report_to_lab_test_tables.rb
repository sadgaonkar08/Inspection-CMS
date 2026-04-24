class AddReportToLabTestTables < ActiveRecord::Migration[7.1]
  def change
    add_reference :lab_test_imports, :report, null: true, foreign_key: true
    add_reference :lab_test_results, :report, null: true, foreign_key: true
    add_index :lab_test_results, [:project_id, :report_id]
  end
end
