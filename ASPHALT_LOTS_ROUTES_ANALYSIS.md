# Search Results: /projects/:id and asphalt-lots Routes

## Overview
This document contains all the relevant code for handling the `/projects/:id` route with the "asphalt-lots" tab, particularly focusing on the view action and error handling.

---

## 1. ROUTES CONFIGURATION

File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/config/routes.rb`

```ruby
# Projects resource with nested asphalt_lots
resources :projects do
  resources :bid_items
  resources :approved_equipments, only: [:create, :destroy]
  resources :phases, only: [:create, :update, :destroy]
  resources :change_orders, only: [:create, :update, :destroy]

  resources :asphalt_lots do
    member do
      get :core_generations_json
      get :management_json
      patch :set_core_lock
    end
    resource :bulk_setup, only: [:new, :create]
    resources :asphalt_sublots, only: [:create, :update, :destroy] do
      member do
        patch :toggle_core_lock
        patch :bulk_update_lanes
      end
      resources :asphalt_lanes, only: [:create, :update, :destroy]
    end
    resources :core_generations, only: [:new, :create, :show] do
      member do
        get :export_csv
        get :export_xlsx
      end
      collection { post :create_for_sublot }
    end
  end

  resources :lab_test_imports, only: [:new, :create, :show, :destroy] do
    member do
      patch :approve
      patch :reject
    end
  end

  resources :lab_test_results, only: [:index, :edit, :update, :destroy] do
    collection do
      get :export_csv
      get :export_xlsx
    end
  end
end

# API endpoints for projects (token-authenticated)
namespace :api do
  namespace :v1 do
    resources :projects, only: [:index, :show] do
      resources :bid_items, only: [] do
        member do
          get :checklist, to: "projects#bid_item_checklist"
        end
      end
      # Lab test and report resources nested under API projects
    end
  end
end
```

**Key Routes:**
- `GET /projects/:id` - Show project view (main route)
- `GET /projects/:id?tab=asphalt-lots` - Asphalt lots tab (via turbo-frame request)
- `GET /projects/:id/asphalt_lots/:asphalt_lot_id` - Show individual asphalt lot
- `GET /projects/:id/asphalt_lots/:asphalt_lot_id/core_generations_json` - JSON API for core generations
- `GET /projects/:id/asphalt_lots/:asphalt_lot_id/management_json` - JSON API for lot management data

---

## 2. CONTROLLER ACTIONS

### ProjectsController
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/controllers/projects_controller.rb`

```ruby
class ProjectsController < ApplicationController
  before_action :set_project, only: %i[ show edit update destroy ]
  before_action :require_admin!, only: %i[ create update destroy ]

  # Main show action with turbo-frame support
  def show
    if turbo_frame_request? && params[:tab].present?
      load_tab_data(params[:tab])
      render :show_tab, layout: false
    end
  end

  # Tab data loader - called for lazy-loaded tabs via turbo-frame
  private
    def load_tab_data(tab)
      case tab
      when "bid-items"
        @bid_items = @project.bid_items.includes(:spec_item).order(:code)
      when "lab-tests"
        @lab_test_imports = @project.lab_test_imports.includes(:asphalt_lot, :report).order(created_at: :desc).limit(10)
        @lab_test_results_summary = @project.lab_test_results.group(:spec_code, :result).count
      when "equipment"
        @approved_equipments = @project.approved_equipments.order(:name)
      when "phases"
        @phases = @project.phases.left_joins(:reports)
                          .select('phases.*, COUNT(reports.id) AS reports_count')
                          .group('phases.id')
                          .order(:name)
      when "change-orders"
        @change_orders = @project.change_orders.order(:number)
      when "asphalt-lots"
        # This is the key handler for the asphalt-lots tab
        @asphalt_lots = @project.asphalt_lots.includes(:asphalt_sublots, :core_generations).order(:lot_number)
      end
    end

    def set_project
      @project = Project.find(params[:id])
    end
end
```

**Key Behaviors:**
1. `show` action checks if request is a turbo-frame request with `tab` parameter
2. If turbo-frame request: calls `load_tab_data` and renders `show_tab.html.erb` without layout
3. If regular request: renders full `show.html.erb` with all tabs
4. For "asphalt-lots" tab: loads asphalt_lots with sublots and core_generations associations

### AsphaltLotsController
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/controllers/asphalt_lots_controller.rb`

```ruby
class AsphaltLotsController < ApplicationController
  before_action :set_project
  before_action :set_asphalt_lot, only: %i[show edit update destroy management_json set_core_lock]

  # Show asphalt lot with full details
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

    @pwl_calculations = @asphalt_lot.pwl_calculations.order(:parameter)
    group_lab_test_results_by_sublot!
  end

  # JSON endpoint for core generations (called by JavaScript)
  def core_generations_json
    @asphalt_lot = @project.asphalt_lots.find(params[:id])
    core_generations = @asphalt_lot.core_generations
                                 .includes(core_locations: [:asphalt_sublot, :asphalt_lane])
                                 .order(created_at: :desc)

    generations = core_generations.map do |cg|
      sorted_locations = cg.core_locations.sort_by do |loc|
        [loc.asphalt_sublot&.position || Float::INFINITY, loc.joint? ? 0 : 1, loc.mark.to_s]
      end
      locations = sorted_locations.map do |loc|
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

  # JSON endpoint for lot management data (called by JavaScript)
  def management_json
    render json: {
      lot: lot_management_payload(@asphalt_lot)
    }
  end

  # Patch endpoint to lock/unlock cores
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
```

### API ProjectsController
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/controllers/api/v1/projects_controller.rb`

```ruby
module Api
  module V1
    class ProjectsController < Api::BaseController
      # GET /api/v1/projects
      def index
        projects = Project.order(:name).map do |p|
          { id: p.id, name: p.name, ... }
        end
        render json: projects
      end

      # GET /api/v1/projects/:id
      def show
        project = Project.find(params[:id])
        render json: {
          id: project.id,
          name: project.name,
          # ... project details
          bid_items: project.bid_items.includes(:spec_item).order(:code).map { |bi|
            # ... bid item details
          }
        }
      end
    end
  end
end
```

---

## 3. ERROR HANDLING

### ApplicationController (Global Error Handler)
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/controllers/application_controller.rb`

```ruby
class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  # Global error handler for RecordNotFound
  rescue_from ActiveRecord::RecordNotFound do
    redirect_to root_path, alert: "You don't have access to that record."
  end
end
```

**Error Handling Flow:**
1. If `Project.find(params[:id])` fails with `ActiveRecord::RecordNotFound`
2. Redirect to root path with alert message
3. Message: "You don't have access to that record."

### API Base Controller
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/controllers/api/base_controller.rb`

```ruby
module Api
  class BaseController < ActionController::API
    before_action :authenticate_api_user!

    private

    def authenticate_api_user!
      token = request.headers["Authorization"]&.remove("Bearer ")
      @current_user = User.authenticate_by_api_token(token)
      render json: { error: "Unauthorized" }, status: :unauthorized unless @current_user
    end
  end
end
```

---

## 4. VIEW FILES

### Project Show View (Main Page)
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/views/projects/show.html.erb`

```erb
<div class="dashboard-container" data-controller="tabs toggle-edit" data-tabs-active-value="overview">
  <div class="dashboard-header">
    <div>
      <h1><%= @project.name %></h1>
      <p class="text-muted mb-0">Contract #<%= @project.contract_number %> · PM: <%= @project.project_manager.presence || "-" %></p>
    </div>
  </div>

  <div class="directory-tab-bar">
    <button type="button" class="directory-tab-btn is-active" data-tabs-target="tab" data-tab="overview">
      Overview
    </button>
    <!-- ... other tabs ... -->
    <button type="button" class="directory-tab-btn" data-tabs-target="tab" data-tab="asphalt-lots">
      Asphalt Lots
    </button>
  </div>

  <div class="directory-panel" data-tabs-target="panel" data-tab="overview">
    <%= render "projects/overview_tab" %>
  </div>

  <% %w[bid-items lab-tests equipment phases change-orders asphalt-lots].each do |tab| %>
    <div class="directory-panel d-none" data-tabs-target="panel" data-tab="<%= tab %>">
      <!-- Lazy-loaded via turbo-frame -->
      <%= turbo_frame_tag "tab-#{tab}", src: project_path(@project, tab: tab), loading: "lazy", target: "_top" do %>
        <p class="text-muted">Loading…</p>
      <% end %>
    </div>
  <% end %>
</div>
```

### Turbo-Frame Response View
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/views/projects/show_tab.html.erb`

```erb
<%# Rendered as a turbo-frame response for lazy tab loading on the project show page. %>
<% partial_name = "projects/#{params[:tab].tr('-', '_')}_tab" %>
<%= turbo_frame_tag "tab-#{params[:tab]}", target: "_top" do %>
  <%= render partial_name %>
<% end %>
```

This dynamically renders `_asphalt_lots_tab.html.erb` when tab is "asphalt-lots"

### Asphalt Lots Tab Partial
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/views/projects/_asphalt_lots_tab.html.erb`

```erb
<div class="d-flex justify-between align-center mb-4">
  <h3 class="mb-0">Asphalt Lots (<%= @asphalt_lots.count %>)</h3>
  <%= link_to "+ New Lot", new_project_asphalt_lot_path(@project), class: "btn btn-primary" %>
</div>

<div class="form-card">
  <% cache [@project, "project_asphalt_lots_tab", @asphalt_lots.cache_key_with_version] do %>
    <% if @asphalt_lots.any? %>
      <table class="modern-table">
        <thead>
          <tr>
            <th>Lot #</th>
            <th>Plant</th>
            <th>Mix Type</th>
            <th>Total Tonnage</th>
            <th>Paving Date</th>
            <th>Sublots</th>
            <th>Generations</th>
            <th class="text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          <% @asphalt_lots.each do |lot| %>
            <tr>
              <td class="cell-primary"><%= lot.lot_number %></td>
              <td><%= lot.plant.presence || "-" %></td>
              <td><%= lot.mix_type.presence || "-" %></td>
              <td><%= lot.total_tonnage.present? ? number_with_precision(...) : "-" %></td>
              <td><%= lot.paving_date&.strftime("%b %d, %Y") || "-" %></td>
              <td><%= lot.asphalt_sublots.size %></td>
              <td><%= lot.core_generations.size %></td>
              <td class="text-right">
                <%= link_to "View", project_asphalt_lot_path(@project, lot), class: "btn btn-secondary btn-sm" %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% else %>
      <p class="text-muted">No asphalt lots have been created for this project yet.</p>
    <% end %>
  <% end %>
</div>
```

### Asphalt Lot Show View
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/views/asphalt_lots/show.html.erb`

Key sections:
- Lot Details (plant, mix type, contractor, etc.)
- PWL Analysis
- Sublots & Lanes management
- Core Generation History (table)
- Individual Sublot cards with lanes (collapsible)
- Lab Test Results (matched and unmatched)
- Core Location Diagram (canvas)

---

## 5. FRONT-END API CALLS

### Core Generation Selector Controller (JavaScript)
File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/javascript/controllers/core_generation_selector_controller.js`

**Key API Calls made by this controller:**

1. **Fetch Core Generations** (Line 216-237)
```javascript
async fetchGenerations(lotId, preferredGenerationId = null) {
  const url = `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/core_generations_json`
  const response = await fetch(url, {
    headers: { "Accept": "application/json" }
  })
  // Returns: { generations: [...], lock_state: {...} }
}
```

2. **Fetch Lot Management Data** (Line 721-733)
```javascript
async fetchLotManagement() {
  const lotId = this.currentLotId()
  const data = await this.requestJson(`/projects/${this.projectIdValue}/asphalt_lots/${lotId}/management_json`)
  // Returns: { lot: {...with sublots and lanes} }
}
```

3. **Create Asphalt Lot** (Line 155-214)
```javascript
// POST /projects/{projectId}/asphalt_lots
// Body: { asphalt_lot: {...}, quick_setup: {...} }
// Response: { lot: {...}, paths: {...} }
```

4. **Generate Core Locations** (Line 639-689)
```javascript
// POST /projects/{projectId}/asphalt_lots/{lotId}/core_generations
// Body: { core_generation: {...} }
```

5. **Set Core Lock** (Line 386-422)
```javascript
// PATCH /projects/{projectId}/asphalt_lots/{lotId}/set_core_lock
// Body: { locked: boolean }
// Response: { lock_state: {...}, message: string }
```

6. **Add/Update Sublots and Lanes** (Various methods)
```javascript
// POST/PATCH/DELETE endpoints for sublots and lanes
// /projects/{projectId}/asphalt_lots/{lotId}/asphalt_sublots
// /projects/{projectId}/asphalt_lots/{lotId}/asphalt_sublots/{sublotId}/asphalt_lanes
```

---

## 6. TABS CONTROLLER (Stimulus)

File: `/Users/sadgaonkar/gitlocal/Inspection-CMS/app/javascript/controllers/tabs_controller.js`

```javascript
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { active: String }

  connect() {
    const hashTab = window.location.hash?.replace("#", "")
    const initialTab = hashTab || this.activeValue || this.tabTargets[0]?.dataset.tab
    if (initialTab) {
      this.show(initialTab)
    }
  }

  switch(event) {
    event.preventDefault()
    const tabId = event.currentTarget.dataset.tab
    if (!tabId) return
    this.show(tabId)
    history.replaceState(null, "", `#${tabId}`)
  }

  show(tabId) {
    this.activeValue = tabId
    this.tabTargets.forEach((tab) => {
      tab.classList.toggle("is-active", tab.dataset.tab === tabId)
    })
    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("d-none", panel.dataset.tab !== tabId)
    })
  }
}
```

**Behavior:**
1. When tab is clicked, `switch` method is called
2. Updates URL hash to `#asphalt-lots`
3. Hides all panels except selected tab
4. Turbo-frame automatically loads content via `src` attribute

---

## 7. REQUEST/RESPONSE FLOW

### Loading `/projects/3` with asphalt-lots tab:

1. **Initial Page Load**
   - GET `/projects/3`
   - ProjectsController#show (no turbo-frame request)
   - Render `show.html.erb` with all tabs
   - Asphalt-lots tab has turbo-frame with `src="/projects/3?tab=asphalt-lots"`

2. **Tab Click or Hash Navigation**
   - Click tab button or navigate to `#asphalt-lots`
   - Tabs controller shows the panel
   - Turbo loads frame from `src="/projects/3?tab=asphalt-lots"`

3. **Turbo-Frame Request**
   - GET `/projects/3?tab=asphalt-lots` (with turbo-frame header)
   - ProjectsController#show detects `turbo_frame_request?` and `params[:tab]`
   - Calls `load_tab_data("asphalt-lots")`
   - Loads `@asphalt_lots = @project.asphalt_lots.includes(:asphalt_sublots, :core_generations).order(:lot_number)`
   - Render `show_tab.html.erb` which renders `_asphalt_lots_tab.html.erb` without layout

4. **Display Asphalt Lots Table**
   - Shows list of lots with summary info
   - Each row has a "View" link to `/projects/3/asphalt_lots/{lot_id}`

5. **View Individual Lot**
   - GET `/projects/3/asphalt_lots/123`
   - AsphaltLotsController#show
   - Load full lot details, sublots, lanes, generations
   - Render `show.html.erb` with details

6. **Dynamic Content via JavaScript**
   - CoreGenerationSelectorController makes fetch requests
   - GET `/projects/3/asphalt_lots/123/core_generations_json` -> JSON
   - GET `/projects/3/asphalt_lots/123/management_json` -> JSON

---

## 8. SUMMARY OF KEY ENDPOINTS

| Method | Path | Controller#Action | Response | Purpose |
|--------|------|-------------------|----------|---------|
| GET | `/projects/3` | projects#show | HTML | Display project overview |
| GET | `/projects/3?tab=asphalt-lots` | projects#show | HTML (turbo-frame) | Load asphalt-lots tab |
| GET | `/projects/3/asphalt_lots` | asphalt_lots#index | Redirect | Redirects to project with anchor |
| GET | `/projects/3/asphalt_lots/123` | asphalt_lots#show | HTML | Display lot details |
| GET | `/projects/3/asphalt_lots/123/core_generations_json` | asphalt_lots#core_generations_json | JSON | Get core generation history |
| GET | `/projects/3/asphalt_lots/123/management_json` | asphalt_lots#management_json | JSON | Get lot management data |
| PATCH | `/projects/3/asphalt_lots/123/set_core_lock` | asphalt_lots#set_core_lock | JSON | Lock/unlock cores |
| POST | `/projects/3/asphalt_lots` | asphalt_lots#create | HTML/JSON | Create new lot |

---

## 9. ERROR HANDLING DETAILS

**RecordNotFound Error:**
- Triggered when: `Project.find(params[:id])` or `AsphaltLot.find(params[:id])` fails
- Handler: `ApplicationController#rescue_from ActiveRecord::RecordNotFound`
- Response: Redirect to `root_path` with alert "You don't have access to that record."
- HTTP Status: 302 (redirect)

**Validation Errors:**
- Returned as JSON in API responses: `{ errors: [...messages...] }`
- HTTP Status: 422 (unprocessable_entity)

**Authorization Errors:**
- Before-action: `require_admin!` on create/update/destroy in ProjectsController
- API: `authenticate_api_user!` in Api::BaseController
- Response: JSON `{ error: "Unauthorized" }` with 401 status
