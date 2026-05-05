require "csv"

class CoreGenerationsController < ApplicationController
  before_action :set_project_and_lot

  def new
    @core_generation = @asphalt_lot.core_generations.build
  end

  def create
    @core_generation = @asphalt_lot.core_generations.build(core_generation_params)

    if @core_generation.save
      begin
        latest = latest_generation(exclude_id: @core_generation.id)
        legacy_locked_ids = @asphalt_lot.asphalt_sublots.where(locked_for_core_generation: true).pluck(:id)

        CoreGenerator.new(@core_generation, locked_sublot_ids: legacy_locked_ids).generate!

        copy_locked_core_locations(latest, @core_generation, legacy_locked_ids: legacy_locked_ids) if latest

        Rails.logger.info("[CoreGeneration] id=#{@core_generation.id} seed=#{@core_generation.seed} lot=#{@asphalt_lot.lot_number}")

        respond_to do |format|
          format.html do
            redirect_to project_asphalt_lot_core_generation_path(@project, @asphalt_lot, @core_generation),
                        notice: "Core locations generated successfully"
          end
          format.json do
            render json: {
              message: "Core locations generated successfully",
              generation: generation_payload(@core_generation)
            }, status: :created
          end
        end
      rescue StandardError => e
        @core_generation.destroy
        respond_to do |format|
          format.html do
            flash.now[:alert] = "Generation failed: #{e.message}"
            render :new, status: :unprocessable_entity
          end
          format.json do
            render json: { errors: ["Generation failed: #{e.message}"] }, status: :unprocessable_entity
          end
        end
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @core_generation.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def create_for_sublot
    @sublot = @asphalt_lot.asphalt_sublots.find(params[:sublot_id])

    if @sublot.locked_for_core_generation
      respond_to do |format|
        format.html do
          redirect_back fallback_location: project_asphalt_lot_path(@project, @asphalt_lot),
                        alert: "Sublot #{@sublot.position} is locked and cannot be regenerated"
        end
        format.json do
          render json: { errors: ["Sublot #{@sublot.position} is locked and cannot be regenerated"] }, status: :unprocessable_entity
        end
      end
      return
    end

    @core_generation = @asphalt_lot.core_generations.build(
      generation_defaults_from_latest.merge(create_for_sublot_generation_params.to_h.compact_blank)
    )

    if @core_generation.save
      begin
        latest = latest_generation(exclude_id: @core_generation.id)
        legacy_locked_ids = @asphalt_lot.asphalt_sublots.where(locked_for_core_generation: true).pluck(:id)
        CoreGenerator.new(@core_generation, target_sublot_ids: [@sublot.id]).generate!

        if latest
          other_ids = @asphalt_lot.asphalt_sublots.where.not(id: @sublot.id).pluck(:id)
          copy_core_locations(latest, @core_generation, other_ids) if other_ids.any?
          copy_locked_core_locations(
            latest,
            @core_generation,
            legacy_locked_ids: legacy_locked_ids,
            sublot_ids: [@sublot.id]
          )
        end

        respond_to do |format|
          format.html do
            redirect_to project_asphalt_lot_core_generation_path(@project, @asphalt_lot, @core_generation),
                        notice: "Core locations generated for Sublot #{@sublot.position}"
          end
          format.json do
            render json: {
              message: "Core locations generated for Sublot #{@sublot.position}",
              generation: generation_payload(@core_generation)
            }, status: :created
          end
        end
      rescue StandardError => e
        @core_generation.destroy
        respond_to do |format|
          format.html do
            flash[:alert] = "Generation failed: #{e.message}"
            redirect_back fallback_location: project_asphalt_lot_path(@project, @asphalt_lot)
          end
          format.json do
            render json: { errors: ["Generation failed: #{e.message}"] }, status: :unprocessable_entity
          end
        end
      end
    else
      respond_to do |format|
        format.html do
          redirect_back fallback_location: project_asphalt_lot_path(@project, @asphalt_lot),
                        alert: @core_generation.errors.full_messages.to_sentence
        end
        format.json do
          render json: { errors: @core_generation.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  def show
    @core_generation = @asphalt_lot.core_generations
                         .includes(core_locations: [:asphalt_lane, :asphalt_sublot, :left_lane, :right_lane])
                         .find(params[:id])
    @recent_generations = @asphalt_lot.core_generations
                                   .includes(:core_locations)
                                   .order(created_at: :desc)
                                   .limit(8)
    @sort_by_sublot = params[:sort] == "sublot"

    @core_locations = if @sort_by_sublot
      @core_generation.core_locations.order(:asphalt_sublot_id, :core_type, :mark)
    else
      @core_generation.core_locations.order(:core_type, :asphalt_sublot_id, :mark)
    end

    @diagram_data = build_diagram_data
  end

  def export_csv
    @core_generation = @asphalt_lot.core_generations
                         .includes(core_locations: [:asphalt_lane, :asphalt_sublot, :left_lane, :right_lane])
                         .find(params[:id])

    locations = @core_generation.core_locations.order(:mark).to_a
    has_adjusted = locations.any?(&:station_adjusted)
    buffer_ft = @core_generation.lane_start_buffer_ft

    csv = CSV.generate do |out|
      # Metadata
      out << ["Core Location Report"]
      out << ["Lot", @asphalt_lot.lot_number, "Mix Type", @asphalt_lot.mix_type]
      out << ["Generated", @core_generation.created_at.strftime("%B %d, %Y %H:%M")]
      out << []

      # Column legend
      out << ["Column Definitions:"]
      out << ["  Sublot Station (ft)", "Random position across total sublot footage (all lanes combined)"]
      out << ["  Lane Station (ft)", "Derived position within the specific lane"]
      out << ["  Offset in Lane (ft)", "Random lateral position within the lane (MAT) or lane boundary (JOINT)"]
      out << ["  Random (A)", "ASTM D3665 random number used for station"]
      out << ["  Random (B)", "ASTM D3665 random number used for offset"]
      out << []

      # Data header
      out << ["Mark", "Type", "Sublot", "Lane", "Lot Dist (ft)",
              "Sublot Station (ft)", "Lane Station (ft)", "Offset in Lane (ft)",
              "Random (A)", "Random (B)"]

      # Data rows
      locations.each do |loc|
        lane_value = if loc.joint?
          left = loc.left_lane&.position
          right = loc.right_lane&.position
          (left.present? && right.present?) ? "lanes #{left}/#{right}" : loc.lane_index
        else
          loc.lane_index
        end

        rand_a = loc.station_random_number.present? ? format("%.4f", loc.station_random_number.to_f) : "N/A"
        rand_b = loc.offset_random_number.present? ? format("%.4f", loc.offset_random_number.to_f) : "N/A"

        out << [
          loc.mark, loc.core_type, loc.asphalt_sublot&.position, lane_value,
          loc.distance_from_lot_start_ft, loc.sublot_station_ft || loc.linear_in_sublot_ft,
          loc.station_in_lane_ft, loc.offset_in_lane_ft,
          rand_a, rand_b
        ]
      end

      # Footnote for adjusted stations
      if has_adjusted
        out << []
        out << ["* adjusted +#{buffer_ft.to_f.round(1)}ft to account for field conditions"]
      end
    end

    send_data csv,
              filename: "lot-#{@asphalt_lot.lot_number}-core-locations-#{@core_generation.id}.csv",
              type: "text/csv"
  end

  def export_xlsx
    @core_generation = @asphalt_lot.core_generations.find(params[:id])
    result = CoreLocationXlsxExporter.new(@core_generation, @asphalt_lot).to_stream

    send_data result[:stream].read,
              filename: result[:filename],
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def set_project_and_lot
    @project = Project.find(params[:project_id])
    @asphalt_lot = @project.asphalt_lots.find(params[:asphalt_lot_id])
  end

  def core_generation_params
    params.fetch(:core_generation, ActionController::Parameters.new).permit(
      :seed, :rounding_increment_ft, :mat_edge_buffer_ft,
      :lane_start_buffer_ft, :mat_cores_per_sublot, :joint_cores_per_joint
    )
  end

  def create_for_sublot_generation_params
    params.fetch(:core_generation, ActionController::Parameters.new).permit(
      :mat_cores_per_sublot,
      :joint_cores_per_joint
    )
  end

  def generation_payload(generation)
    sorted_core_locations = generation.core_locations.includes(:asphalt_sublot, :asphalt_lane).sort_by do |loc|
      [loc.asphalt_sublot&.position || Float::INFINITY, loc.joint? ? 0 : 1, loc.mark.to_s]
    end
    locations = sorted_core_locations.map do |loc|
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
      id: generation.id,
      seed: generation.seed,
      created_at: generation.created_at.strftime("%b %d, %Y %H:%M"),
      location_count: locations.size,
      locations: locations
    }
  end

  def latest_generation(exclude_id: nil)
    scope = @asphalt_lot.core_generations.order(created_at: :desc)
    scope = scope.where.not(id: exclude_id) if exclude_id
    scope.first
  end

  def generation_defaults_from_latest
    latest = latest_generation
    return {} unless latest

    {
      rounding_increment_ft: latest.rounding_increment_ft,
      mat_edge_buffer_ft: latest.mat_edge_buffer_ft,
      lane_start_buffer_ft: latest.lane_start_buffer_ft,
      mat_cores_per_sublot: latest.mat_cores_per_sublot,
      joint_cores_per_joint: latest.joint_cores_per_joint
    }
  end

  def build_diagram_data
    sublots = @asphalt_lot.asphalt_sublots.order(:position).includes(:asphalt_lanes)
    all_locations = @core_generation.core_locations.to_a

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
      buffer_ft: @core_generation.lane_start_buffer_ft.to_f
    }
  end

  def copy_core_locations(from_generation, to_generation, sublot_ids, core_types: nil)
    return if from_generation.nil? || sublot_ids.empty?

    scope = from_generation.core_locations.where(asphalt_sublot_id: sublot_ids)
    scope = scope.where(core_type: core_types) if core_types.present?

    scope.find_each do |loc|
      CoreLocation.create!(
        core_generation: to_generation,
        asphalt_lot: loc.asphalt_lot,
        asphalt_sublot: loc.asphalt_sublot,
        asphalt_lane: loc.asphalt_lane,
        left_lane: loc.left_lane,
        right_lane: loc.right_lane,
        core_type: loc.core_type,
        lane_index: loc.lane_index,
        sublot_station_ft: loc.sublot_station_ft,
        linear_in_sublot_ft: loc.linear_in_sublot_ft,
        station_in_lane_ft: loc.station_in_lane_ft,
        offset_in_lane_ft: loc.offset_in_lane_ft,
        distance_from_lot_start_ft: loc.distance_from_lot_start_ft,
        mark: loc.mark,
        station_adjusted: loc.station_adjusted,
        station_random_number: loc.station_random_number,
        offset_random_number: loc.offset_random_number
      )
    end
  end

  def copy_locked_core_locations(from_generation, to_generation, legacy_locked_ids:, sublot_ids: nil)
    return if from_generation.nil?

    scope = @asphalt_lot.asphalt_sublots
    scope = scope.where(id: sublot_ids) if sublot_ids.present?

    scope.find_each do |sublot|
      core_types = locked_core_types_for(sublot, legacy_locked_ids)
      next if core_types.empty?

      copy_core_locations(from_generation, to_generation, [sublot.id], core_types: core_types)
    end
  end

  def locked_core_types_for(sublot, legacy_locked_ids)
    return %i[mat joint] if legacy_locked_ids.include?(sublot.id)
    return %i[mat joint] if sublot.lock_all?

    [].tap do |types|
      types << :mat if sublot.mat_locked?
      types << :joint if sublot.joint_locked?
    end
  end
end
