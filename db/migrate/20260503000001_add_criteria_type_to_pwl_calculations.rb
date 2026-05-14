class AddCriteriaTypeToPwlCalculations < ActiveRecord::Migration[7.1]
  def change
    add_column :pwl_calculations, :criteria_type, :string, default: "pwl", null: false
    add_column :pwl_calculations, :passed, :boolean
  end
end
