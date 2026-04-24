class CreateLabTestResults < ActiveRecord::Migration[7.1]
  def change
    create_table :lab_test_results do |t|
      t.references :project, null: false, foreign_key: true
      t.references :lab_test_import, null: false, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.string :spec_code, null: false
      t.string :lab_name
      t.date :report_date
      t.date :test_date
      t.string :sublot_number
      t.jsonb :data, default: {}, null: false
      t.string :result
      t.text :notes

      t.timestamps
    end

    add_index :lab_test_results, [:project_id, :spec_code]
    add_index :lab_test_results, [:project_id, :result]
    add_index :lab_test_results, [:project_id, :test_date]
  end
end
