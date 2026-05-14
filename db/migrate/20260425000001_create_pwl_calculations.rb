class CreatePwlCalculations < ActiveRecord::Migration[7.1]
  def change
    create_table :pwl_calculations do |t|
      t.references :asphalt_lot, null: false, foreign_key: true
      t.string :parameter, null: false
      t.integer :n
      t.jsonb :sample_values, default: [], null: false
      t.decimal :mean, precision: 10, scale: 4
      t.decimal :std_dev, precision: 10, scale: 4
      t.decimal :lower_limit, precision: 10, scale: 4
      t.decimal :upper_limit, precision: 10, scale: 4
      t.decimal :q_lower, precision: 10, scale: 4
      t.decimal :q_upper, precision: 10, scale: 4
      t.integer :p_lower
      t.integer :p_upper
      t.integer :pwl_percentage
      t.string :status, null: false
      t.datetime :calculated_at

      t.timestamps
    end

    add_index :pwl_calculations, [:asphalt_lot_id, :parameter], unique: true
  end
end
