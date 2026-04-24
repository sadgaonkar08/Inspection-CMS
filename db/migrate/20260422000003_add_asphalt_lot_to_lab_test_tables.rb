class AddAsphaltLotToLabTestTables < ActiveRecord::Migration[7.1]
  def change
    add_reference :lab_test_imports, :asphalt_lot, null: true, foreign_key: true
    add_reference :lab_test_results, :asphalt_lot, null: true, foreign_key: true
    add_index :lab_test_results, [:project_id, :asphalt_lot_id]
  end
end
