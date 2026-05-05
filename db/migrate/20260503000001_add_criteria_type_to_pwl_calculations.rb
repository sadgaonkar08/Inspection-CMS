class AddCriteriaTypeToPwlCalculations < ActiveRecord::Migration[7.1]
  def change
    # Check if table exists before adding columns
    return unless table_exists?(:pwl_calculations)

    add_column :pwl_calculations, :criteria_type, :string, default: "pwl", null: false unless column_exists?(:pwl_calculations, :criteria_type)
    add_column :pwl_calculations, :passed, :boolean unless column_exists?(:pwl_calculations, :passed)
  end
end
