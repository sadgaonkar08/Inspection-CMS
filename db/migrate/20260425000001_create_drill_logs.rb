class CreateDrillLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :drill_logs do |t|
      # Project association
      t.references :project, null: false, foreign_key: true

      # Basic information
      t.string :boring_number
      t.string :client
      t.string :project_name
      t.string :project_number
      t.string :project_location

      # Dates and elevation
      t.date :date_started
      t.date :date_completed
      t.decimal :ground_elevation, precision: 10, scale: 2
      t.string :hole_size

      # Drilling information
      t.string :drilling_contractor
      t.string :drilling_method
      t.string :drill_rig
      t.string :hammer_weight
      t.string :sampling_device
      t.string :casing_size

      # Personnel
      t.string :logged_by
      t.string :checked_by

      # Water levels
      t.string :water_level_at_drilling
      t.string :water_level_at_end

      # Depths
      t.decimal :total_depth, precision: 10, scale: 2
      t.decimal :overburden, precision: 10, scale: 2

      # Coordinates (optional)
      t.decimal :northing, precision: 12, scale: 2
      t.decimal :easting, precision: 12, scale: 2

      # Additional notes
      t.text :notes

      # JSON data for layers and samples
      t.jsonb :layers, default: [], null: false
      t.jsonb :samples, default: [], null: false

      # Metadata
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # Add indexes
    add_index :drill_logs, :boring_number
    add_index :drill_logs, [:project_id, :boring_number], unique: true
    add_index :drill_logs, :date_started
    add_index :drill_logs, :layers, using: :gin
    add_index :drill_logs, :samples, using: :gin
  end
end