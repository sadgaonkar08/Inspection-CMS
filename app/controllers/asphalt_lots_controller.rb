class AsphaltLotsController < ApplicationController
  before_action :set_project
  before_action :set_asphalt_lot, only: %i[show edit update destroy management_json set_core_lock]

  def index
    redirect_to project_path(@project, anchor: "asphalt-lots")
  end

  def show
    @all_lots = @project.asphalt_lots.order(:lot_number)
    @generation_history = @asphalt_lot.core_generations
                                 .includes(:core_locations)
                                 .order(created_at: :desc)
                                 .limit(20)

    @latest_generation = @generation_history.first
    @latest_generation = @asphalt_lot.core_generations
                           .includes(core_locations: [:asphalt_sublot, :asphalt_lane, :left_lane, :right_lane])
                           .find(@latest_generation.id) if @latest_generation

    if @latest_generation
      @diagram_data = build_lot_diagram_data(@latest_generation)
    end

    group_lab_test_results_by_sublot!
  end

  def new
    @asphalt_lot = @project.asphalt_lots.build
  end

  def edit
  end

  def create
    @asphalt_lot = @project.asphalt_lots.build(asphalt_lot_params)

    begin
      ActiveRecord::Base.transaction do
        @asphalt_lot.save!
        apply_quick_setup!(@asphalt_lot)
      end

      respond_to do |format|
        format.html do
          redirect_to project_asphalt_lot_path(@project, @asphalt_lot), notice: "Asphalt lot was successfully created."
        end
        format.json do
          render json: {
            lot: {
              id: @asphalt_lot.id,
              lot_number: @asphalt_lot.lot_number,
              mix_type: @asphalt_lot.mix_type,
              plant: @asphalt_lot.plant,
              sublots_count: @asphalt_lot.asphalt_sublots.count
            },
            paths: {
              lot_path: project_asphalt_lot_path(@project, @asphalt_lot),
              generate_path: new_project_asphalt_lot_core_generation_path(@project, @asphalt_lot)
            }
          }, status: :created
        end
      end
    rescue ActiveRecord::RecordInvalid
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @asphalt_lot.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @asphalt_lot.update(asphalt_lot_params)
      respond_to do |format|
        format.html do
          redirect_to project_asphalt_lot_path(@project, @asphalt_lot), notice: "Asphalt lot was successfully updated.", status: :see_other
        end
        format.json { render json: { lot: lot_summary(@asphalt_lot) }, status: :ok }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @asphalt_lot.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @asphalt_lot.destroy!

    respond_to do |format|
      format.html do
        redirect_to project_path(@project, anchor: "asphalt-lots"), notice: "Asphalt lot was successfully deleted.", status: :see_other
      end
      format.json { head :no_content }
    end
  end

  def core_generations_json
    @asphalt_lot = @project.asphalt_lots.find(params[:id])
    core_generations = @asphalt_lot.core_generations
                                 .includes(core_locations: [:asphalt_sublot, :asphalt_lane])
                                 .order(created_at: :desc)

    generations = core_generations.map do |cg|
      locations = cg.core_locations.sort_by { |loc| loc.mark.to_s }.map do |loc|
        {
          mark: loc.mark,
          core_type: loc.mat? ? "Mat" : "Joint",
          sublot: loc.asphalt_sublot&.position,
          lane: loc.lane_index,
          station_ft: loc.station_in_lane_ft&.to_f&.round(1),
          offset_ft: loc.offset_in_lane_ft&.to_f&.round(1)
        }
      end
      {
        id: cg.id,
        seed: cg.seed,
        created_at: cg.created_at.strftime("%b %d, %Y %H:%M"),
        location_count: locations.size,
        locations: locations
      }
    end

    render json: {
      generations: generations,
      lock_state: lock_state_payload(@asphalt_lot)
    }
  end

  def management_json
    render json: {
      lot: lot_management_payload(@asphalt_lot)
    }
  end

  def set_core_lock
    lock_value = ActiveModel::Type::Boolean.new.cast(params[:locked])
    @asphalt_lot.asphalt_sublots.update_all(locked_for_core_generation: lock_value)

    render json: {
      lock_state: lock_state_payload(@asphalt_lot),
      message: lock_value ? "Core locations locked in place for this lot." : "Core locations unlocked for this lot."
    }, status: :ok
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_asphalt_lot
    @asphalt_lot = @project.asphalt_lots.find(params[:id])
  end

  def asphalt_lot_params
    params.require(:asphalt_lot).permit(:lot_number, :plant, :mix_type, :contractor, :mix_design, :pg, :description, :paving_date, :total_tonnage)
  end

  def quick_setup_params
    params.fetch(:quick_setup, ActionController::Parameters.new).permit(:num_sublots, :lanes_per_sublot, :lane_length_ft, :lane_width_ft)
  end

  def apply_quick_setup!(lot)
    setup = quick_setup_params
    return if setup.blank?

    num_sublots = setup[:num_sublots].to_i
    lanes_per_sublot = setup[:lanes_per_sublot].to_i
    return if num_sublots <= 0 || lanes_per_sublot <= 0

    lane_length = setup[:lane_length_ft].presence || "500"
    lane_width = setup[:lane_width_ft].presence || "12"
    starting_position = lot.asphalt_sublots.maximum(:position).to_i

    num_sublots.times do |sublot_index|
      sublot_position = starting_position + sublot_index + 1
      sublot = lot.asphalt_sublots.create!(
        position: sublot_position,
        name: "Sublot #{sublot_position}"
      )

      lanes_per_sublot.times do |lane_index|
        lane_position = lane_index + 1
        sublot.asphalt_lanes.create!(
          position: lane_position,
          name: "Lane #{lane_position}",
          length_ft: lane_length,
          width_ft: lane_width
        )
      end
    end
  end

  def lot_summary(lot)
    {
      id: lot.id,
      lot_number: lot.lot_number,
      mix_type: lot.mix_type,
      plant: lot.plant,
      total_tonnage: lot.total_tonnage,
      sublots_count: lot.asphalt_sublots.count
    }
  end

  def lock_state_payload(lot)
    total_sublots = lot.asphalt_sublots.count
    locked_sublots = lot.asphalt_sublots.where(locked_for_core_generation: true).count

    {
      total_sublots: total_sublots,
      locked_sublots: locked_sublots,
      all_locked: total_sublots.positive? && locked_sublots == total_sublots,
      any_locked: locked_sublots.positive?
    }
  end

  def group_lab_test_results_by_sublot!
    results = @asphalt_lot.lab_test_results
                          .includes(:lab_test_import)
                          .order(Arel.sql("test_date DESC NULLS LAST, report_date DESC NULLS LAST, id DESC"))

    sublots_by_key = @asphalt_lot.asphalt_sublots.index_by { |s| normalize_sublot_key(s.position) }

    @lab_results_by_sublot_id = Hash.new { |h, k| h[k] = [] }
    @unmatched_lab_results = []

    results.each do |r|
      key = normalize_sublot_key(r.sublot_number)
      sublot = key.present? ? sublots_by_key[key] : nil
      if sublot
        @lab_results_by_sublot_id[sublot.id] << r
      else
        @unmatched_lab_results << r
      end
    end
  end

  def normalize_sublot_key(value)
    return nil if value.nil?
    str = value.to_s.strip
    return nil if str.empty?
    if (m = str.match(/(?:sublot|sl)[\s#_-]*(\d+)/i))
      return m[1].sub(/\A0+(?=\d)/, '')
    end
    if (m = str.match(/(\d+)\z/))
      return m[1].sub(/\A0+(?=\d)/, '')
    end
    str.sub(/\A0+(?=\d)/, '').downcase
  end

  def build_lot_diagram_data(generation)
    sublots = @asphalt_lot.asphalt_sublots.order(:position).includes(:asphalt_lanes)
    all_locations = generation.core_locations.to_a

    {
      sublots: sublots.map { |sublot|
        {
          position: sublot.position,
          lanes: sublot.asphalt_lanes.order(:position).map { |lane|
            { position: lane.position, length_ft: lane.length_ft.to_f, width_ft: lane.width_ft.to_f }
          },
          cores: all_locations.select { |c| c.asphalt_sublot_id == sublot.id }.map { |c|
            {
              mark: c.mark, type: c.core_type,
              lane_position: c.lane_index,
              left_lane: c.left_lane&.position, right_lane: c.right_lane&.position,
              station_ft: c.station_in_lane_ft.to_f,
              offset_ft: c.offset_in_lane_ft.to_f,
              adjusted: c.station_adjusted || false
            }
          }
        }
      },
      buffer_ft: generation.lane_start_buffer_ft.to_f
    }
  end

  def lot_management_payload(lot)
    {
      id: lot.id,
      lot_number: lot.lot_number,
      plant: lot.plant,
      mix_type: lot.mix_type,
      contractor: lot.contractor,
      mix_design: lot.mix_design,
      pg: lot.pg,
      description: lot.description,
      paving_date: lot.paving_date,
      total_tonnage: lot.total_tonnage,
      core_generations_count: lot.core_generations.count,
      sublots: lot.asphalt_sublots.order(:position).includes(:asphalt_lanes).map do |sublot|
        {
          id: sublot.id,
          position: sublot.position,
          name: sublot.name,
          locked_for_core_generation: sublot.locked_for_core_generation,
          core_lock_mode: sublot.core_lock_mode,
          lanes: sublot.asphalt_lanes.order(:position).map do |lane|
            {
              id: lane.id,
              position: lane.position,
              length_ft: lane.length_ft.to_f,
              width_ft: lane.width_ft.to_f
            }
          end
        }
      end
    }
  end
end
