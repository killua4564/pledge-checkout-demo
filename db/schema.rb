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

ActiveRecord::Schema[8.1].define(version: 2026_11_25_000001) do
  create_table "addons", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "title", null: false
    t.decimal "price", precision: 12, scale: 2, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_addons_on_project_id"
  end

  create_table "discount_codes", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "code", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "code"], name: "index_discount_codes_on_project_id_and_code", unique: true
    t.index ["project_id"], name: "index_discount_codes_on_project_id"
  end

  create_table "order_addons", force: :cascade do |t|
    t.integer "order_id", null: false
    t.integer "addon_id", null: false
    t.string "title", null: false
    t.decimal "price", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["addon_id"], name: "index_order_addons_on_addon_id"
    t.index ["order_id", "addon_id"], name: "index_order_addons_on_order_id_and_addon_id", unique: true
    t.index ["order_id"], name: "index_order_addons_on_order_id"
  end

  create_table "order_discounts", force: :cascade do |t|
    t.integer "order_id", null: false
    t.integer "discount_code_id", null: false
    t.string "code", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discount_code_id"], name: "index_order_discounts_on_discount_code_id"
    t.index ["order_id"], name: "index_order_discounts_on_order_id", unique: true
  end

  create_table "order_transitions", force: :cascade do |t|
    t.integer "order_id", null: false
    t.string "from_status", null: false
    t.string "to_status", null: false
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_transitions_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "public_id", null: false
    t.string "checkout_token", null: false
    t.integer "project_id", null: false
    t.integer "reward_id", null: false
    t.string "status", default: "pending_payment", null: false
    t.string "currency", null: false
    t.decimal "reward_amount", precision: 12, scale: 2, null: false
    t.decimal "addons_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "discount_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "shipping_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "donation_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 12, scale: 2, null: false
    t.string "payment_method", null: false
    t.datetime "expires_at"
    t.string "ship_region", null: false
    t.string "ship_city"
    t.string "ship_district"
    t.string "ship_zip"
    t.string "ship_address"
    t.string "recipient_name"
    t.string "recipient_phone"
    t.string "invoice_type", default: "personal", null: false
    t.string "carrier_code"
    t.string "company_tax_id"
    t.string "company_title"
    t.datetime "paid_at"
    t.datetime "failed_at"
    t.datetime "cancelled_at"
    t.datetime "expired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checkout_token"], name: "index_orders_on_checkout_token", unique: true
    t.index ["project_id"], name: "index_orders_on_project_id"
    t.index ["public_id"], name: "index_orders_on_public_id", unique: true
    t.index ["reward_id"], name: "index_orders_on_reward_id"
    t.index ["status", "expires_at"], name: "index_orders_on_status_and_expires_at"
  end

  create_table "payment_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_id"
    t.integer "payment_id"
    t.boolean "signature_valid", null: false
    t.text "raw_body"
    t.string "result", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id"], name: "index_payment_events_on_payment_id"
    t.index ["provider", "event_id"], name: "index_payment_events_on_provider_and_event_id", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.integer "order_id", null: false
    t.string "payment_method", null: false
    t.string "provider", null: false
    t.string "provider_trade_no", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "currency", null: false
    t.string "status", default: "pending", null: false
    t.string "review_reason"
    t.string "virtual_account"
    t.datetime "pay_deadline"
    t.json "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["provider", "provider_trade_no"], name: "index_payments_on_provider_and_provider_trade_no", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.string "summary"
    t.text "description"
    t.string "cover_image_url"
    t.string "currency", default: "TWD", null: false
    t.decimal "funding_goal", precision: 12, scale: 2
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  create_table "rewards", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "image_url"
    t.decimal "list_price", precision: 12, scale: 2
    t.decimal "price", precision: 12, scale: 2, null: false
    t.integer "quota_total", null: false
    t.integer "quota_taken", default: 0, null: false
    t.date "estimated_delivery_on"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_rewards_on_project_id"
    t.check_constraint "quota_taken >= 0 AND quota_taken <= quota_total", name: "rewards_quota_within_limit"
  end

  create_table "shipping_rates", force: :cascade do |t|
    t.integer "reward_id", null: false
    t.string "region", null: false
    t.string "label", null: false
    t.decimal "fee", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "addon_fee", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reward_id", "region"], name: "index_shipping_rates_on_reward_id_and_region", unique: true
    t.index ["reward_id"], name: "index_shipping_rates_on_reward_id"
  end

  add_foreign_key "addons", "projects"
  add_foreign_key "discount_codes", "projects"
  add_foreign_key "order_addons", "addons"
  add_foreign_key "order_addons", "orders"
  add_foreign_key "order_discounts", "discount_codes"
  add_foreign_key "order_discounts", "orders"
  add_foreign_key "order_transitions", "orders"
  add_foreign_key "orders", "projects"
  add_foreign_key "orders", "rewards"
  add_foreign_key "payment_events", "payments"
  add_foreign_key "payments", "orders"
  add_foreign_key "rewards", "projects"
  add_foreign_key "shipping_rates", "rewards"
end
