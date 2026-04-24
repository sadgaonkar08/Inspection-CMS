class AddTotalTonnageToAsphaltLots < ActiveRecord::Migration[7.1]
  def change
    add_column :asphalt_lots, :total_tonnage, :decimal, precision: 12, scale: 2
  end
end
