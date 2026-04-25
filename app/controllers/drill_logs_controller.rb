class DrillLogsController < ApplicationController
  before_action :set_project
  before_action :set_drill_log, only: %i[ show edit update destroy ]

  # GET /projects/1/drill_logs → redirect to project show with drill-logs tab
  def index
    redirect_to project_path(@project, anchor: "drill-logs")
  end

  # GET /projects/1/drill_logs/1
  def show
    # Show individual drill log with report view
  end

  # GET /projects/1/drill_logs/new
  def new
    @drill_log = @project.drill_logs.build
  end

  # POST /projects/1/drill_logs
  def create
    @drill_log = @project.drill_logs.build(drill_log_params)
    @drill_log.created_by = current_user if current_user

    if @drill_log.save
      redirect_to project_path(@project, anchor: "drill-logs"), notice: "Drill log created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /projects/1/drill_logs/1/edit
  def edit
  end

  # PATCH /projects/1/drill_logs/1
  def update
    @drill_log.updated_by = current_user if current_user

    if @drill_log.update(drill_log_params)
      redirect_to project_path(@project, anchor: "drill-logs"), notice: "Drill log updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /projects/1/drill_logs/1
  def destroy
    @drill_log.destroy
    redirect_to project_path(@project, anchor: "drill-logs"), notice: "Drill log deleted successfully."
  end

  private
    def set_project
      @project = Project.find(params[:project_id])
    end

    def set_drill_log
      @drill_log = @project.drill_logs.find(params[:id])
    end

    def drill_log_params
      params.require(:drill_log).permit(
        # Basic information
        :boring_number,
        :client,
        :project_name,
        :project_number,
        :project_location,

        # Dates and elevation
        :date_started,
        :date_completed,
        :ground_elevation,
        :hole_size,

        # Drilling information
        :drilling_contractor,
        :drilling_method,
        :drill_rig,
        :hammer_weight,
        :sampling_device,
        :casing_size,

        # Personnel
        :logged_by,
        :checked_by,

        # Water levels
        :water_level_at_drilling,
        :water_level_at_end,

        # Depths
        :total_depth,
        :overburden,

        # Coordinates
        :northing,
        :easting,

        # Notes
        :notes,

        # JSON arrays - Rails will handle these as arrays
        layers: [:from, :to, :uscs, :desc, :change],
        samples: [:depth, :id, :type, :blows, :desc, :ll, :pi, :gravel, :sand, :fines, :rec, :mc, :pid, :remarks]
      )
    end
end