class LabTestLotResolver
  # Pulls the lot prefix from labels emitted by AME multi-lot cores reports
  # ("L3/SL3" → "3", "L 4/SL1" → "4"). Single-lot reports use a "TS"/"TS2" prefix
  # which doesn't carry a lot number; those return nil so the caller falls back
  # to the import's user-selected asphalt_lot_id.
  LOT_PREFIX_RE = /\AL\s*(\d+)\s*\//i.freeze

  def initialize(project)
    @project = project
  end

  def resolve(sublot_number)
    return nil if sublot_number.blank?
    m = sublot_number.to_s.match(LOT_PREFIX_RE)
    return nil unless m
    lots_by_number[m[1]]&.id
  end

  private

  def lots_by_number
    @lots_by_number ||= @project.asphalt_lots.index_by(&:lot_number)
  end
end
