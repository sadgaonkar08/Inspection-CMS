class AddHesToLabTestResults < ActiveRecord::Migration[7.1]
  def change
    add_column :lab_test_results, :hes, :boolean, default: false, null: false
  end
end
