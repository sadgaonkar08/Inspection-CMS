class ProjectsController < ApplicationController
  before_action :set_project, only: %i[ show edit update destroy ]
  before_action :require_admin!, only: %i[ create update destroy ]

  def index
    @projects = Project.includes(:bid_items).order(:name)
    @spec_items = SpecItem.order(:division, :code)
    @spec_divisions = @spec_items.map(&:division).compact.uniq
  end

  def show
    load_project_collections
  end

  def new
    @project = Project.new
  end

  def edit
    redirect_to project_path(@project, anchor: "overview")
  end

  def create
    @project = Project.new(project_params)

    respond_to do |format|
      if @project.save
        format.html { redirect_to @project, notice: "Project was successfully created." }
        format.json { render :show, status: :created, location: @project }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @project.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @project.update(project_params)
        format.html { redirect_to project_path(@project, anchor: "overview"), notice: "Project was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @project }
      else
        format.html {
          load_project_collections
          render :show, status: :unprocessable_entity
        }
        format.json { render json: @project.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if @project.bid_items.joins(:placed_quantities).exists?
      redirect_to @project, alert: "Cannot delete this project because placed quantities are recorded. Remove those entries first."
      return
    end

    @project.destroy!

    respond_to do |format|
      format.html { redirect_to projects_path, notice: "Project was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  rescue ActiveRecord::DeleteRestrictionError => e
    redirect_to @project, alert: e.message
  end

  private
    def set_project
      @project = Project.find(params[:id])
    end

    def project_params
      params.require(:project).permit(:name, :contract_number, :project_manager, :construction_manager, :contract_days, :contract_start_date, :prime_contractor, :latitude, :longitude)
    end

    def load_project_collections
      @bid_items = @project.bid_items.includes(:spec_item).order(:code)
      @asphalt_lots = @project.asphalt_lots.includes(:asphalt_sublots, :core_generations).order(:lot_number)
      @lab_test_imports = @project.lab_test_imports.includes(:asphalt_lot, :report).order(created_at: :desc).limit(10)
      @lab_test_results_summary = @project.lab_test_results
                                           .group(:spec_code, :result)
                                           .count
      @phases = @project.phases.left_joins(:reports)
                        .select('phases.*, COUNT(reports.id) AS reports_count')
                        .group('phases.id')
                        .order(:name)
      @approved_equipments = @project.approved_equipments.order(:name)
      @change_orders = @project.change_orders.order(:number)
    end

    def require_admin!
      return if current_user&.admin?

      respond_to do |format|
        format.html { redirect_to projects_path, alert: "You are not authorized to modify projects." }
        format.json { render json: { error: "Forbidden" }, status: :forbidden }
      end
    end
end
