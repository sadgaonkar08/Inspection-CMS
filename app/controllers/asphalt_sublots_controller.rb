class AsphaltSublotsController < ApplicationController
  before_action :set_project_and_lot
  before_action :set_sublot, only: %i[update destroy toggle_core_lock bulk_update_lanes]

  def create
    attrs = sublot_params.to_h
    attrs["position"] = @asphalt_lot.asphalt_sublots.maximum(:position).to_i + 1 if attrs["position"].blank?
    attrs["name"] = "Sublot #{attrs['position']}" if attrs["name"].blank?

    @sublot = @asphalt_lot.asphalt_sublots.build(attrs)

    if @sublot.save
      respond_to do |format|
        format.html { redirect_to project_asphalt_lot_path(@project, @asphalt_lot), notice: "Sublot created." }
        format.json { render json: { sublot: sublot_payload(@sublot) }, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to project_asphalt_lot_path(@project, @asphalt_lot), alert: @sublot.errors.full_messages.to_sentence }
        format.json { render json: { errors: @sublot.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @sublot.update(sublot_params)
      respond_to do |format|
        format.html { redirect_to project_asphalt_lot_path(@project, @asphalt_lot), notice: "Sublot updated.", status: :see_other }
        format.json { render json: { sublot: sublot_payload(@sublot) }, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to project_asphalt_lot_path(@project, @asphalt_lot), alert: @sublot.errors.full_messages.to_sentence }
        format.json { render json: { errors: @sublot.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @sublot.destroy!

    respond_to do |format|
      format.html { redirect_to project_asphalt_lot_path(@project, @asphalt_lot), notice: "Sublot deleted.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def bulk_update_lanes
    lanes_attrs = params.require(:lanes).permit!.to_h
    errors = []

    ActiveRecord::Base.transaction do
      lanes_attrs.each do |lane_id, attrs|
        lane = @sublot.asphalt_lanes.find(lane_id)
        permitted = attrs.slice("length_ft", "width_ft")
        unless lane.update(permitted)
          errors << "Lane #{lane.position}: #{lane.errors.full_messages.to_sentence}"
        end
      end
      raise ActiveRecord::Rollback if errors.any?
    end

    respond_to do |format|
      if errors.any?
        format.html { redirect_to project_asphalt_lot_path(@project, @asphalt_lot), alert: errors.join("; ") }
        format.json { render json: { errors: errors }, status: :unprocessable_entity }
      else
        format.html { redirect_to project_asphalt_lot_path(@project, @asphalt_lot), notice: "Lanes updated.", status: :see_other }
        format.json { render json: { ok: true }, status: :ok }
      end
    end
  end

  def toggle_core_lock
    if params[:core_lock_mode].present?
      @sublot.update!(core_lock_mode: params[:core_lock_mode])
    else
      # Legacy toggle: flip between none and all
      new_mode = @sublot.lock_none? ? :all : :none
      @sublot.update!(core_lock_mode: new_mode)
    end

    respond_to do |format|
      format.html { redirect_back fallback_location: project_asphalt_lot_path(@project, @asphalt_lot) }
      format.json { render json: { sublot: sublot_payload(@sublot) }, status: :ok }
    end
  end

  private

  def set_project_and_lot
    @project = Project.find(params[:project_id])
    @asphalt_lot = @project.asphalt_lots.find(params[:asphalt_lot_id])
  end

  def set_sublot
    @sublot = @asphalt_lot.asphalt_sublots.find(params[:id])
  end

  def sublot_params
    params.require(:asphalt_sublot).permit(:position, :name)
  end

  def sublot_payload(sublot)
    {
      id: sublot.id,
      position: sublot.position,
      name: sublot.name,
      locked_for_core_generation: sublot.locked_for_core_generation,
      core_lock_mode: sublot.core_lock_mode
    }
  end
end
