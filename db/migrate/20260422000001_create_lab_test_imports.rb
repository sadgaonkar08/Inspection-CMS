class CreateLabTestImports < ActiveRecord::Migration[7.1]
  def change
    create_table :lab_test_imports do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :spec_code, null: false
      t.string :lab_name
      t.string :status, null: false, default: "pending"
      t.text :raw_text
      t.jsonb :report_header, default: {}, null: false
      t.jsonb :parsed_data, default: [], null: false
      t.jsonb :extraction_errors, default: [], null: false
      t.integer :row_count, default: 0, null: false

      t.timestamps
    end

    add_index :lab_test_imports, [:project_id, :status, :created_at]
    add_index :lab_test_imports, [:project_id, :spec_code]
  end
end
