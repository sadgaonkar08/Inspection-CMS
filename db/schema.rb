# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_05_03_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activity_logs", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "user_id", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_id"], name: "index_activity_logs_on_report_id"
    t.index ["user_id"], name: "index_activity_logs_on_user_id"
  end

  create_table "approved_equipments", force: :cascade do |t|
    t.string "name"
    t.bigint "project_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category"
    t.index ["project_id"], name: "index_approved_equipments_on_project_id"
  end

  create_table "asphalt_lanes", force: :cascade do |t|
    t.bigint "asphalt_sublot_id", null: false
    t.integer "position", null: false
    t.string "name"
    t.decimal "length_ft", precision: 10, scale: 2, null: false
    t.decimal "width_ft", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asphalt_sublot_id", "position"], name: "index_asphalt_lanes_on_asphalt_sublot_id_and_position", unique: true
    t.index ["asphalt_sublot_id"], name: "index_asphalt_lanes_on_asphalt_sublot_id"
  end

  create_table "asphalt_lots", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "lot_number", null: false
    t.string "plant"
    t.string "mix_type"
    t.string "contractor"
    t.string "mix_design"
    t.string "pg"
    t.text "description"
    t.date "paving_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "total_tonnage", precision: 12, scale: 2
    t.index ["project_id", "plant", "mix_type", "lot_number"], name: "index_asphalt_lots_on_project_plant_mix_lot_number", unique: true
    t.index ["project_id"], name: "index_asphalt_lots_on_project_id"
  end

  create_table "asphalt_sublots", force: :cascade do |t|
    t.bigint "asphalt_lot_id", null: false
    t.integer "position", null: false
    t.string "name"
    t.boolean "locked_for_core_generation", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "core_lock_mode", default: 0, null: false
    t.index ["asphalt_lot_id", "position"], name: "index_asphalt_sublots_on_asphalt_lot_id_and_position", unique: true
    t.index ["asphalt_lot_id"], name: "index_asphalt_sublots_on_asphalt_lot_id"
  end

  create_table "astm_random_numbers", force: :cascade do |t|
    t.integer "row", null: false
    t.integer "column", null: false
    t.decimal "value", precision: 10, scale: 4, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["row", "column"], name: "index_astm_random_numbers_on_row_and_column", unique: true
  end

  create_table "bid_items", force: :cascade do |t|
    t.string "code"
    t.string "description"
    t.string "unit"
    t.jsonb "checklist_questions"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "spec_item_id", null: false
    t.bigint "project_id"
    t.decimal "bid_quantity", precision: 15, scale: 3
    t.string "sov_category"
    t.string "trade_package"
    t.index ["project_id", "code"], name: "index_bid_items_on_project_id_and_code", unique: true
    t.index ["project_id"], name: "index_bid_items_on_project_id"
    t.index ["sov_category"], name: "index_bid_items_on_sov_category"
    t.index ["spec_item_id"], name: "index_bid_items_on_spec_item_id"
    t.index ["trade_package"], name: "index_bid_items_on_trade_package"
  end

  create_table "change_orders", force: :cascade do |t|
    t.integer "number", null: false
    t.text "description"
    t.string "status", default: "active"
    t.date "approved_date"
    t.bigint "project_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "number"], name: "index_change_orders_on_project_id_and_number", unique: true
    t.index ["project_id"], name: "index_change_orders_on_project_id"
  end

  create_table "checklist_entries", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "spec_item_id", null: false
    t.jsonb "checklist_answers"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_id"], name: "index_checklist_entries_on_report_id"
    t.index ["spec_item_id"], name: "index_checklist_entries_on_spec_item_id"
  end

  create_table "context_snippets", force: :cascade do |t|
    t.integer "category", null: false
    t.string "spec_code"
    t.string "spec_section"
    t.string "activity"
    t.string "title", null: false
    t.text "content", null: false
    t.string "tags", default: [], array: true
    t.integer "token_count", default: 0
    t.boolean "active", default: true
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_context_snippets_on_active", where: "(active = true)"
    t.index ["category"], name: "index_context_snippets_on_category"
    t.index ["spec_code"], name: "index_context_snippets_on_spec_code"
    t.index ["spec_section"], name: "index_context_snippets_on_spec_section"
    t.index ["tags"], name: "index_context_snippets_on_tags", using: :gin
  end

  create_table "core_generations", force: :cascade do |t|
    t.bigint "asphalt_lot_id", null: false
    t.string "seed"
    t.decimal "rounding_increment_ft", precision: 10, scale: 2, default: "0.5"
    t.decimal "mat_edge_buffer_ft", precision: 10, scale: 2, default: "1.0"
    t.decimal "lane_start_buffer_ft", precision: 10, scale: 2, default: "10.0"
    t.integer "mat_cores_per_sublot", default: 1
    t.integer "joint_cores_per_joint", default: 1
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asphalt_lot_id"], name: "index_core_generations_on_asphalt_lot_id"
  end

  create_table "core_locations", force: :cascade do |t|
    t.bigint "core_generation_id", null: false
    t.bigint "asphalt_lot_id", null: false
    t.bigint "asphalt_sublot_id", null: false
    t.bigint "asphalt_lane_id", null: false
    t.bigint "left_lane_id"
    t.bigint "right_lane_id"
    t.integer "core_type", null: false
    t.integer "lane_index"
    t.decimal "linear_in_sublot_ft", precision: 12, scale: 2
    t.decimal "station_in_lane_ft", precision: 12, scale: 2
    t.decimal "offset_in_lane_ft", precision: 12, scale: 2
    t.decimal "distance_from_lot_start_ft", precision: 12, scale: 2
    t.string "mark"
    t.decimal "station_random_number", precision: 10, scale: 4
    t.decimal "offset_random_number", precision: 10, scale: 4
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "sublot_station_ft", precision: 12, scale: 2
    t.boolean "station_adjusted", default: false, null: false
    t.index ["asphalt_lane_id"], name: "index_core_locations_on_asphalt_lane_id"
    t.index ["asphalt_lot_id"], name: "index_core_locations_on_asphalt_lot_id"
    t.index ["asphalt_sublot_id"], name: "index_core_locations_on_asphalt_sublot_id"
    t.index ["core_generation_id", "asphalt_sublot_id"], name: "index_core_locations_on_generation_and_sublot"
    t.index ["core_generation_id"], name: "index_core_locations_on_core_generation_id"
    t.index ["left_lane_id"], name: "index_core_locations_on_left_lane_id"
    t.index ["right_lane_id"], name: "index_core_locations_on_right_lane_id"
  end

  create_table "crew_entries", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.string "contractor"
    t.integer "laborer_count"
    t.integer "operator_count"
    t.integer "survey_count"
    t.integer "electrician_count"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "foreman_count", default: 0
    t.integer "superintendent_count", default: 0
    t.index ["report_id"], name: "index_crew_entries_on_report_id"
  end

  create_table "equipment_entries", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.string "contractor"
    t.string "make_model"
    t.integer "quantity", default: 1
    t.decimal "hours"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "remarks"
    t.index ["report_id"], name: "index_equipment_entries_on_report_id"
  end

  create_table "imported_reports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_id"
    t.string "status", default: "imported", null: false
    t.string "contract_number"
    t.string "project_title"
    t.float "template_confidence"
    t.text "template_errors"
    t.jsonb "parsed_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contract_number"], name: "index_imported_reports_on_contract_number"
    t.index ["project_id"], name: "index_imported_reports_on_project_id"
    t.index ["status"], name: "index_imported_reports_on_status"
    t.index ["user_id"], name: "index_imported_reports_on_user_id"
  end

  create_table "lab_test_imports", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.string "spec_code", null: false
    t.string "lab_name"
    t.string "status", default: "pending", null: false
    t.text "raw_text"
    t.jsonb "report_header", default: {}, null: false
    t.jsonb "parsed_data", default: [], null: false
    t.jsonb "extraction_errors", default: [], null: false
    t.integer "row_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "asphalt_lot_id"
    t.bigint "report_id"
    t.index ["asphalt_lot_id"], name: "index_lab_test_imports_on_asphalt_lot_id"
    t.index ["project_id", "spec_code"], name: "index_lab_test_imports_on_project_id_and_spec_code"
    t.index ["project_id", "status", "created_at"], name: "index_lab_test_imports_on_project_id_and_status_and_created_at"
    t.index ["project_id"], name: "index_lab_test_imports_on_project_id"
    t.index ["report_id"], name: "index_lab_test_imports_on_report_id"
    t.index ["user_id"], name: "index_lab_test_imports_on_user_id"
  end

  create_table "lab_test_results", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "lab_test_import_id", null: false
    t.bigint "created_by_id"
    t.string "spec_code", null: false
    t.string "lab_name"
    t.date "report_date"
    t.date "test_date"
    t.string "sublot_number"
    t.jsonb "data", default: {}, null: false
    t.string "result"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "asphalt_lot_id"
    t.bigint "report_id"
    t.boolean "hes", default: false, null: false
    t.index ["asphalt_lot_id"], name: "index_lab_test_results_on_asphalt_lot_id"
    t.index ["created_by_id"], name: "index_lab_test_results_on_created_by_id"
    t.index ["lab_test_import_id"], name: "index_lab_test_results_on_lab_test_import_id"
    t.index ["project_id", "asphalt_lot_id"], name: "index_lab_test_results_on_project_id_and_asphalt_lot_id"
    t.index ["project_id", "report_id"], name: "index_lab_test_results_on_project_id_and_report_id"
    t.index ["project_id", "result"], name: "index_lab_test_results_on_project_id_and_result"
    t.index ["project_id", "spec_code"], name: "index_lab_test_results_on_project_id_and_spec_code"
    t.index ["project_id", "test_date"], name: "index_lab_test_results_on_project_id_and_test_date"
    t.index ["project_id"], name: "index_lab_test_results_on_project_id"
    t.index ["report_id"], name: "index_lab_test_results_on_report_id"
  end

  create_table "phases", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "project_id", null: false
    t.index ["project_id"], name: "index_phases_on_project_id"
  end

  create_table "placed_quantities", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "bid_item_id", null: false
    t.decimal "quantity"
    t.text "notes"
    t.jsonb "checklist_answers", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "location"
    t.bigint "change_order_id"
    t.index ["bid_item_id"], name: "index_placed_quantities_on_bid_item_id"
    t.index ["change_order_id"], name: "index_placed_quantities_on_change_order_id"
    t.index ["report_id", "bid_item_id"], name: "index_placed_quantities_on_report_and_bid_item"
    t.index ["report_id"], name: "index_placed_quantities_on_report_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "contract_number"
    t.string "project_manager"
    t.string "construction_manager"
    t.integer "contract_days"
    t.date "contract_start_date"
    t.string "prime_contractor"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
  end

  create_table "pwl_calculations", force: :cascade do |t|
    t.bigint "asphalt_lot_id", null: false
    t.string "parameter", null: false
    t.integer "n"
    t.jsonb "sample_values", default: [], null: false
    t.decimal "mean", precision: 10, scale: 4
    t.decimal "std_dev", precision: 10, scale: 4
    t.decimal "lower_limit", precision: 10, scale: 4
    t.decimal "upper_limit", precision: 10, scale: 4
    t.decimal "q_lower", precision: 10, scale: 4
    t.decimal "q_upper", precision: 10, scale: 4
    t.integer "p_lower"
    t.integer "p_upper"
    t.integer "pwl_percentage"
    t.string "status", null: false
    t.datetime "calculated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "criteria_type", default: "pwl", null: false
    t.boolean "passed"
    t.index ["asphalt_lot_id", "parameter"], name: "index_pwl_calculations_on_asphalt_lot_id_and_parameter", unique: true
    t.index ["asphalt_lot_id"], name: "index_pwl_calculations_on_asphalt_lot_id"
  end

  create_table "qa_entries", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.integer "qa_type"
    t.string "location"
    t.integer "result"
    t.string "remarks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_id"], name: "index_qa_entries_on_report_id"
  end

  create_table "report_attachments", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.string "caption"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_id"], name: "index_report_attachments_on_report_id"
  end

  create_table "report_core_generations", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "core_generation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["core_generation_id"], name: "index_report_core_generations_on_core_generation_id"
    t.index ["report_id", "core_generation_id"], name: "index_report_core_generations_unique", unique: true
    t.index ["report_id"], name: "index_report_core_generations_on_report_id"
  end

  create_table "report_exports", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "user_id", null: false
    t.string "status", default: "queued", null: false
    t.integer "progress", default: 0, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_id"], name: "index_report_exports_on_report_id"
    t.index ["status"], name: "index_report_exports_on_status"
    t.index ["user_id"], name: "index_report_exports_on_user_id"
  end

  create_table "reports", force: :cascade do |t|
    t.string "dir_number"
    t.date "start_date"
    t.date "end_date"
    t.bigint "project_id"
    t.bigint "phase_id"
    t.bigint "user_id", null: false
    t.integer "status"
    t.integer "result"
    t.string "shift_start"
    t.string "shift_end"
    t.integer "temp_1"
    t.integer "temp_2"
    t.integer "temp_3"
    t.string "wind_1"
    t.string "wind_2"
    t.string "wind_3"
    t.string "precip_1"
    t.string "precip_2"
    t.string "precip_3"
    t.string "weather_summary_1"
    t.string "weather_summary_2"
    t.string "weather_summary_3"
    t.string "contractor"
    t.string "plan_sheet"
    t.string "relevant_docs"
    t.string "station_start"
    t.string "station_end"
    t.integer "deficiency_status"
    t.text "deficiency_desc"
    t.integer "traffic_control"
    t.integer "environmental"
    t.integer "security"
    t.integer "safety_incident"
    t.text "safety_desc"
    t.integer "air_ops_coordination", default: 0
    t.integer "swppp_controls", default: 0
    t.text "commentary"
    t.text "additional_activities"
    t.text "additional_info"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "visibility_1"
    t.string "visibility_2"
    t.string "visibility_3"
    t.string "surface_conditions"
    t.integer "phasing_compliance", default: 0
    t.text "phasing_compliance_note"
    t.text "traffic_control_note"
    t.text "environmental_note"
    t.text "security_note"
    t.text "air_ops_note"
    t.text "swppp_note"
    t.string "notable_weather_events"
    t.datetime "authorized_date"
    t.integer "contract_day"
    t.text "ai_work_summary"
    t.text "ai_generated_commentary"
    t.string "ai_status", default: "idle"
    t.datetime "ai_generated_at"
    t.text "ai_error"
    t.tsvector "searchable_tsvector"
    t.bigint "authorized_by_id"
    t.string "ai_stage"
    t.index ["ai_status"], name: "index_reports_on_ai_status"
    t.index ["authorized_by_id"], name: "index_reports_on_authorized_by_id"
    t.index ["phase_id"], name: "index_reports_on_phase_id"
    t.index ["project_id", "status", "start_date"], name: "index_reports_on_project_status_start_date"
    t.index ["project_id", "status"], name: "index_reports_on_project_id_and_status"
    t.index ["project_id"], name: "index_reports_on_project_id"
    t.index ["result"], name: "index_reports_on_result"
    t.index ["searchable_tsvector"], name: "index_reports_on_searchable_tsvector", using: :gin
    t.index ["start_date"], name: "index_reports_on_start_date"
    t.index ["status"], name: "index_reports_on_status"
    t.index ["user_id", "status"], name: "index_reports_on_user_id_and_status"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "spec_items", force: :cascade do |t|
    t.string "code"
    t.string "description"
    t.jsonb "checklist_questions"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "division"
    t.index ["code"], name: "index_spec_items_on_code", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0, null: false
    t.string "provider"
    t.string "uid"
    t.string "oid"
    t.string "preferred_username"
    t.string "first_name"
    t.string "last_name"
    t.string "api_token_digest"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["oid"], name: "index_users_on_oid", unique: true, where: "(oid IS NOT NULL)"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "weekly_reports", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "report_number"
    t.integer "status", default: 0, null: false
    t.text "weather_summary"
    t.jsonb "weather_data_json", default: {}
    t.jsonb "completion_data_json", default: {}
    t.text "work_summary"
    t.text "lab_testing_summary"
    t.text "materials_summary"
    t.text "problem_areas"
    t.string "ai_status", default: "idle"
    t.text "ai_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "end_date"], name: "index_weekly_reports_on_project_id_and_end_date", unique: true
    t.index ["project_id", "report_number"], name: "index_weekly_reports_on_project_id_and_report_number", unique: true
    t.index ["project_id"], name: "index_weekly_reports_on_project_id"
    t.index ["user_id"], name: "index_weekly_reports_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activity_logs", "reports"
  add_foreign_key "activity_logs", "users"
  add_foreign_key "approved_equipments", "projects"
  add_foreign_key "asphalt_lanes", "asphalt_sublots"
  add_foreign_key "asphalt_lots", "projects"
  add_foreign_key "asphalt_sublots", "asphalt_lots"
  add_foreign_key "bid_items", "projects"
  add_foreign_key "bid_items", "spec_items"
  add_foreign_key "change_orders", "projects"
  add_foreign_key "checklist_entries", "reports"
  add_foreign_key "checklist_entries", "spec_items"
  add_foreign_key "core_generations", "asphalt_lots"
  add_foreign_key "core_locations", "asphalt_lanes"
  add_foreign_key "core_locations", "asphalt_lots"
  add_foreign_key "core_locations", "asphalt_sublots"
  add_foreign_key "core_locations", "core_generations"
  add_foreign_key "crew_entries", "reports"
  add_foreign_key "equipment_entries", "reports"
  add_foreign_key "imported_reports", "projects"
  add_foreign_key "imported_reports", "users"
  add_foreign_key "lab_test_imports", "asphalt_lots"
  add_foreign_key "lab_test_imports", "projects"
  add_foreign_key "lab_test_imports", "reports"
  add_foreign_key "lab_test_imports", "users"
  add_foreign_key "lab_test_results", "asphalt_lots"
  add_foreign_key "lab_test_results", "lab_test_imports"
  add_foreign_key "lab_test_results", "projects"
  add_foreign_key "lab_test_results", "reports"
  add_foreign_key "lab_test_results", "users", column: "created_by_id"
  add_foreign_key "phases", "projects"
  add_foreign_key "placed_quantities", "bid_items"
  add_foreign_key "placed_quantities", "change_orders"
  add_foreign_key "placed_quantities", "reports"
  add_foreign_key "pwl_calculations", "asphalt_lots"
  add_foreign_key "qa_entries", "reports"
  add_foreign_key "report_attachments", "reports"
  add_foreign_key "report_core_generations", "core_generations"
  add_foreign_key "report_core_generations", "reports"
  add_foreign_key "report_exports", "reports"
  add_foreign_key "report_exports", "users"
  add_foreign_key "reports", "phases"
  add_foreign_key "reports", "projects"
  add_foreign_key "reports", "users"
  add_foreign_key "reports", "users", column: "authorized_by_id"
  add_foreign_key "weekly_reports", "projects"
  add_foreign_key "weekly_reports", "users"
end
