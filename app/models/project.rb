class Project < ApplicationRecord
  # --- 1. Associations ---
  # The Project acts as the "Library" for this specific contract
  has_many :bid_items, dependent: :destroy
  has_many :approved_equipments, dependent: :destroy
  has_many :phases, dependent: :destroy
  has_many :reports, dependent: :nullify
  has_many :weekly_reports, dependent: :destroy
  has_many :asphalt_lots, dependent: :destroy
  has_many :change_orders, dependent: :destroy
  has_many :lab_test_imports, dependent: :destroy
  has_many :lab_test_results, dependent: :destroy
  
  # A "Shortcut" to see which Universal Specs are being used on this job
  has_many :spec_items, through: :bid_items
  
  # --- 2. Validations ---
  validates :name, presence: true, uniqueness: true
  # We validate the new header fields to ensure data quality
  validates :contract_number, presence: true
end