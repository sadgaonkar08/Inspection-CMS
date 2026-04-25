class DrillLog < ApplicationRecord
  # Associations
  belongs_to :project
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  # Validations
  validates :boring_number, presence: true
  validates :boring_number, uniqueness: { scope: :project_id, message: "must be unique within the project" }

  # USCS Soil Classification Options
  USCS_CLASSIFICATIONS = [
    # Surface / Fill
    { value: "PCC", label: "PCC – Portland Cement Concrete" },
    { value: "AB", label: "AB – Aggregate Base" },
    { value: "FILL", label: "FILL" },
    { value: "TS", label: "TS – Topsoil" },

    # Gravels
    { value: "GW", label: "GW – Well-graded GRAVEL" },
    { value: "GP", label: "GP – Poorly graded GRAVEL" },
    { value: "GW-GM", label: "GW-GM – Well-graded GRAVEL w/ SILT" },
    { value: "GW-GC", label: "GW-GC – Well-graded GRAVEL w/ CLAY" },
    { value: "GP-GM", label: "GP-GM – Poorly graded GRAVEL w/ SILT" },
    { value: "GP-GC", label: "GP-GC – Poorly graded GRAVEL w/ CLAY" },
    { value: "GM", label: "GM – SILTY GRAVEL" },
    { value: "GC", label: "GC – CLAYEY GRAVEL" },
    { value: "GC-GM", label: "GC-GM – SILTY, CLAYEY GRAVEL" },

    # Sands
    { value: "SW", label: "SW – Well-graded SAND" },
    { value: "SP", label: "SP – Poorly graded SAND" },
    { value: "SW-SM", label: "SW-SM – Well-graded SAND w/ SILT" },
    { value: "SW-SC", label: "SW-SC – Well-graded SAND w/ CLAY" },
    { value: "SP-SM", label: "SP-SM – Poorly graded SAND w/ SILT" },
    { value: "SP-SC", label: "SP-SC – Poorly graded SAND w/ CLAY" },
    { value: "SM", label: "SM – SILTY SAND" },
    { value: "SC", label: "SC – CLAYEY SAND" },
    { value: "SC-SM", label: "SC-SM – SILTY, CLAYEY SAND" },

    # Fine-Grained
    { value: "CL", label: "CL – Lean CLAY" },
    { value: "CL-ML", label: "CL-ML – Sandy Silty CLAY" },
    { value: "ML", label: "ML – SILT" },
    { value: "OL", label: "OL – Organic lean CLAY" },
    { value: "CH", label: "CH – Fat CLAY" },
    { value: "MH", label: "MH – Elastic SILT" },
    { value: "OH", label: "OH – Organic fat CLAY" }
  ].freeze

  # Drilling Methods
  DRILLING_METHODS = [
    "Mud Rotary",
    "Hollow Stem Auger",
    "Solid Stem Auger",
    "Air Rotary",
    "Diamond Core",
    "Dynamic Cone / Hand Driven"
  ].freeze

  # Sampling Devices
  SAMPLING_DEVICES = [
    "Split Spoon 2-inch",
    "Split Spoon 2.5-inch",
    "Standard California Sampler",
    "Modified California Sampler",
    "Shelby Tube",
    "Piston Sampler"
  ].freeze

  # Sample Types
  SAMPLE_TYPES = [
    { value: "SPT", label: "SPT – Standard Penetration Test" },
    { value: "CA", label: "Standard California Sampler" },
    { value: "MCA", label: "Modified California Sampler" },
    { value: "ST", label: "Shelby Tube" },
    { value: "PS", label: "Piston Sampler" },
    { value: "GB", label: "Grab / Bulk Sample" }
  ].freeze

  # Layer boundary types
  BOUNDARY_TYPES = [
    { value: "solid", label: "Solid (Definite Material Change)" },
    { value: "dashed", label: "Dashed (Estimated Material Change)" },
    { value: "wavy", label: "Wavy (Soil/Rock Boundary)" }
  ].freeze

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_boring_number, -> { order(:boring_number) }
  scope :for_project, ->(project_id) { where(project_id: project_id) }

  # Callbacks
  before_validation :set_defaults

  # Instance methods
  def total_layers
    layers.is_a?(Array) ? layers.length : 0
  end

  def total_samples
    samples.is_a?(Array) ? samples.length : 0
  end

  def max_depth
    max_from_layers = layers.is_a?(Array) && layers.any? ? layers.map { |l| l["to"].to_f }.max : 0
    max_from_samples = samples.is_a?(Array) && samples.any? ? samples.map { |s| s["depth"].to_f }.max : 0
    [max_from_layers, max_from_samples, total_depth.to_f].max
  end

  def display_name
    "#{boring_number} - #{project_name}"
  end

  private

  def set_defaults
    self.layers ||= []
    self.samples ||= []
    self.project_name ||= project&.name if project
    self.client ||= "AECOM" # Default client
  end
end