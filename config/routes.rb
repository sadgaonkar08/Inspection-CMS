# config/routes.rb
Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    registrations:      "users/registrations"
  }

  resource :api_token, only: [:create]
  
  resources :reports do
    resources :checklist_entries, only: [:create, :update, :destroy]
    collection do
      get :import
      post :import_docx
      get :data_view
      get :copy_candidates
    end
    member do
      post :submit_for_qc
      post :approve
      post :request_revision
      post :start_export # Async export with progress tracking
      get  :ai_payload   # Testing: AI payload preview
      get  "sections/:section", action: :show_section, as: :section
      
      # AI generation endpoints
      post :generate_work_summary
      post :generate_commentary
      get  :ai_status
    end
    
    resources :report_exports, only: [:show] do
      member do
        get :download
      end
    end
  end

  # --- MAESTRO CHANGE: Nest Bid Items under Projects ---
  resources :projects do
    resources :bid_items # URL: /projects/1/bid_items/new
    resources :drill_logs # URL: /projects/1/drill_logs
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
        member { patch :toggle_core_lock }
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
  
  resources :weekly_reports do
    member do
      post :generate
      post :export
      get :ai_status
    end
  end

  resources :spec_items, only: [:index, :update]
  
  # ── JSON API (token-authenticated) ────────────────────────────────
  namespace :api do
    namespace :v1 do
      resources :projects, only: [:index, :show] do
        resources :bid_items, only: [] do
          member do
            get :checklist, to: "projects#bid_item_checklist"
          end
        end

        resources :lab_test_imports, only: [:index, :create, :show, :destroy] do
          member do
            patch :approve
            patch :reject
          end
        end

        resources :lab_test_results, only: [:index, :show, :update, :destroy] do
          collection do
            get :export_csv
            get :export_xlsx
          end
        end
      end

      resources :reports, only: [:index, :show, :create, :update] do
        member do
          post :generate_work_summary
          post :generate_commentary
          get  :ai_status
        end
      end

      resources :weekly_reports, only: [:index, :show, :create, :update] do
        member do
          post :generate
          get  :ai_status
        end
      end
    end
  end

  # Lightweight health check for offline indicator heartbeat
  get '/health_check', to: proc { [200, {}, ['']] }

  root "reports#index"
end