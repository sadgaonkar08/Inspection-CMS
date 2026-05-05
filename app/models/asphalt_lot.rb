class AsphaltLot < ApplicationRecord
  PLANTS = ['Santa Clara', 'Pleasanton'].freeze
  MIX_TYPES = ['P-401', 'P-403', 'PG 64-10'].freeze

  belongs_to :project

  has_many :asphalt_sublots, -> { order(:position) }, dependent: :destroy
  has_many :asphalt_lanes, through: :asphalt_sublots
  has_many :core_generations, dependent: :destroy
  has_many :lab_test_results, dependent: :nullify
  has_many :pwl_calculations, dependent: :destroy

  validates :lot_number, presence: true
  validates :plant, presence: true, inclusion: { in: PLANTS }
  validates :mix_type, presence: true, inclusion: { in: MIX_TYPES }
  validates :lot_number, uniqueness: { scope: [:project_id, :plant, :mix_type], message: "already exists for this plant and mix type" }
  validates :total_tonnage, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :for_plant, ->(plant) { where(plant: plant) if plant.present? }
  scope :for_mix, ->(mix_type) { where(mix_type: mix_type) if mix_type.present? }
end
