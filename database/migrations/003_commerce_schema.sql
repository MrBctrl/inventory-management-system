-- Inventory & Sales Management System
-- Migration 003: suppliers, customers, purchasing, sales, payments, returns and expenses
-- Requires migrations 001_core_schema.sql and 002_inventory_schema.sql.

BEGIN;

-- Business contacts ---------------------------------------------------------

CREATE TABLE suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    name VARCHAR(180) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(40),
    address TEXT,
    tax_number VARCHAR(80),
    notes TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT suppliers_business_id_id_unique UNIQUE (business_id, id)
);
CREATE INDEX suppliers_business_name_idx ON suppliers (business_id, LOWER(name));
CREATE INDEX suppliers_business_active_idx ON suppliers (business_id, is_active);

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    full_name VARCHAR(180) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(40),
    address TEXT,
    notes TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT customers_business_id_id_unique UNIQUE (business_id, id)
);
CREATE INDEX customers_business_name_idx ON customers (business_id, LOWER(full_name));
CREATE INDEX customers_business_phone_idx ON customers (business_id, phone) WHERE phone IS NOT NULL;
CREATE INDEX customers_business_email_ci_idx ON customers (business_id, LOWER(email)) WHERE email IS NOT NULL;

-- Purchasing ---------------------------------------------------------------

CREATE TABLE purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    supplier_id UUID NOT NULL,
    location_id UUID NOT NULL,
    purchase_number VARCHAR(60) NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expected_at DATE,
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    subtotal NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    discount_total NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (discount_total >= 0),
    tax_total NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (tax_total >= 0),
    shipping_cost NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (shipping_cost >= 0),
    total_amount NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    notes TEXT,
    created_by UUID NOT NULL,
    ordered_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT purchase_orders_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT purchase_orders_number_unique UNIQUE (business_id, purchase_number),
    CONSTRAINT purchase_orders_supplier_same_business_fk
        FOREIGN KEY (business_id, supplier_id) REFERENCES suppliers (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_orders_location_same_business_fk
        FOREIGN KEY (business_id, location_id) REFERENCES locations (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_orders_created_by_member_fk
        FOREIGN KEY (business_id, created_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT purchase_orders_expected_date_check CHECK (expected_at IS NULL OR expected_at >= order_date)
);
CREATE INDEX purchase_orders_business_status_date_idx
    ON purchase_orders (business_id, status, order_date DESC);
CREATE INDEX purchase_orders_supplier_idx
    ON purchase_orders (business_id, supplier_id, order_date DESC);
CREATE INDEX purchase_orders_location_idx
    ON purchase_orders (business_id, location_id, order_date DESC);

CREATE TABLE purchase_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    purchase_order_id UUID NOT NULL,
    variant_id UUID NOT NULL,
    quantity_ordered NUMERIC(14, 3) NOT NULL CHECK (quantity_ordered > 0),
    unit_cost NUMERIC(14, 2) NOT NULL CHECK (unit_cost >= 0),
    discount_amount NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    line_total NUMERIC(14, 2) NOT NULL CHECK (line_total >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT purchase_items_order_variant_unique UNIQUE (purchase_order_id, variant_id),
    CONSTRAINT purchase_items_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT purchase_items_order_same_business_fk
        FOREIGN KEY (business_id, purchase_order_id)
        REFERENCES purchase_orders (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_items_variant_same_business_fk
        FOREIGN KEY (business_id, variant_id)
        REFERENCES product_variants (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_items_discount_limit_check
        CHECK (discount_amount <= quantity_ordered * unit_cost)
);
CREATE INDEX purchase_items_variant_idx ON purchase_items (business_id, variant_id);

-- A purchase can arrive in multiple deliveries. Only posted receipt items
-- should create inventory movements and increase the stock balance.
CREATE TABLE purchase_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    purchase_order_id UUID NOT NULL,
    receipt_number VARCHAR(60) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'posted', 'cancelled')),
    received_by UUID NOT NULL,
    posted_by UUID,
    posted_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT purchase_receipts_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT purchase_receipts_number_unique UNIQUE (business_id, receipt_number),
    CONSTRAINT purchase_receipts_order_same_business_fk
        FOREIGN KEY (business_id, purchase_order_id)
        REFERENCES purchase_orders (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_receipts_received_by_member_fk
        FOREIGN KEY (business_id, received_by)
        REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT purchase_receipts_posted_by_member_fk
        FOREIGN KEY (business_id, posted_by)
        REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT purchase_receipts_posting_fields_check
        CHECK (status <> 'posted' OR (posted_by IS NOT NULL AND posted_at IS NOT NULL))
);
CREATE INDEX purchase_receipts_order_idx
    ON purchase_receipts (business_id, purchase_order_id, created_at DESC);

CREATE TABLE purchase_receipt_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    receipt_id UUID NOT NULL,
    purchase_item_id UUID NOT NULL,
    quantity_received NUMERIC(14, 3) NOT NULL CHECK (quantity_received > 0),
    unit_cost NUMERIC(14, 2) NOT NULL CHECK (unit_cost >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT purchase_receipt_items_receipt_item_unique UNIQUE (receipt_id, purchase_item_id),
    CONSTRAINT purchase_receipt_items_receipt_same_business_fk
        FOREIGN KEY (business_id, receipt_id)
        REFERENCES purchase_receipts (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_receipt_items_purchase_item_same_business_fk
        FOREIGN KEY (business_id, purchase_item_id)
        REFERENCES purchase_items (business_id, id) ON DELETE RESTRICT
);
CREATE INDEX purchase_receipt_items_purchase_item_idx
    ON purchase_receipt_items (business_id, purchase_item_id);

-- Sales --------------------------------------------------------------------

CREATE TABLE sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    location_id UUID NOT NULL,
    customer_id UUID,
    order_number VARCHAR(60) NOT NULL,
    external_order_id VARCHAR(120),
    channel VARCHAR(20) NOT NULL CHECK (channel IN ('in_store', 'online')),
    status VARCHAR(24) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'confirmed', 'processing', 'completed', 'cancelled')),
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    subtotal NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    discount_total NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (discount_total >= 0),
    tax_total NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (tax_total >= 0),
    shipping_amount NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (shipping_amount >= 0),
    total_amount NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    notes TEXT,
    created_by UUID,
    completed_by UUID,
    completed_at TIMESTAMPTZ,
    cancelled_by UUID,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT sales_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT sales_order_number_unique UNIQUE (business_id, order_number),
    CONSTRAINT sales_external_order_unique UNIQUE (business_id, channel, external_order_id),
    CONSTRAINT sales_location_same_business_fk
        FOREIGN KEY (business_id, location_id) REFERENCES locations (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT sales_customer_same_business_fk
        FOREIGN KEY (business_id, customer_id) REFERENCES customers (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT sales_created_by_member_fk
        FOREIGN KEY (business_id, created_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT sales_completed_by_member_fk
        FOREIGN KEY (business_id, completed_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT sales_cancelled_by_member_fk
        FOREIGN KEY (business_id, cancelled_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT sales_in_store_actor_check CHECK (channel <> 'in_store' OR created_by IS NOT NULL),
    CONSTRAINT sales_completion_fields_check
        CHECK (status <> 'completed' OR (completed_by IS NOT NULL AND completed_at IS NOT NULL)),
    CONSTRAINT sales_cancellation_fields_check
        CHECK (status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL))
);
CREATE INDEX sales_business_status_date_idx ON sales (business_id, status, created_at DESC);
CREATE INDEX sales_location_date_idx ON sales (business_id, location_id, created_at DESC);
CREATE INDEX sales_customer_date_idx ON sales (business_id, customer_id, created_at DESC) WHERE customer_id IS NOT NULL;

CREATE TABLE sale_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    sale_id UUID NOT NULL,
    variant_id UUID NOT NULL,
    quantity NUMERIC(14, 3) NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(14, 2) NOT NULL CHECK (unit_price >= 0),
    unit_cost_snapshot NUMERIC(14, 2) NOT NULL CHECK (unit_cost_snapshot >= 0),
    discount_amount NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    line_total NUMERIC(14, 2) NOT NULL CHECK (line_total >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT sale_items_sale_variant_unique UNIQUE (sale_id, variant_id),
    CONSTRAINT sale_items_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT sale_items_sale_same_business_fk
        FOREIGN KEY (business_id, sale_id) REFERENCES sales (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT sale_items_variant_same_business_fk
        FOREIGN KEY (business_id, variant_id) REFERENCES product_variants (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT sale_items_discount_limit_check CHECK (discount_amount <= quantity * unit_price)
);
CREATE INDEX sale_items_variant_idx ON sale_items (business_id, variant_id);

-- Payments can be receipts from customers or payments to suppliers.
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    payment_direction VARCHAR(24) NOT NULL
        CHECK (payment_direction IN ('customer_payment', 'supplier_payment')),
    sale_id UUID,
    purchase_order_id UUID,
    amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    payment_method VARCHAR(30) NOT NULL
        CHECK (payment_method IN ('cash', 'card', 'bank_transfer', 'mobile_money', 'payment_gateway', 'other')),
    status VARCHAR(20) NOT NULL DEFAULT 'completed'
        CHECK (status IN ('pending', 'completed', 'failed', 'voided')),
    provider VARCHAR(80),
    provider_reference VARCHAR(160),
    notes TEXT,
    created_by UUID,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT payments_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT payments_sale_same_business_fk
        FOREIGN KEY (business_id, sale_id) REFERENCES sales (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT payments_purchase_same_business_fk
        FOREIGN KEY (business_id, purchase_order_id) REFERENCES purchase_orders (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT payments_created_by_member_fk
        FOREIGN KEY (business_id, created_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT payments_document_direction_check CHECK (
        (payment_direction = 'customer_payment' AND sale_id IS NOT NULL AND purchase_order_id IS NULL)
        OR
        (payment_direction = 'supplier_payment' AND purchase_order_id IS NOT NULL AND sale_id IS NULL)
    ),
    CONSTRAINT payments_paid_at_check CHECK (status <> 'completed' OR paid_at IS NOT NULL)
);
CREATE INDEX payments_sale_status_idx ON payments (business_id, sale_id, status) WHERE sale_id IS NOT NULL;
CREATE INDEX payments_purchase_status_idx ON payments (business_id, purchase_order_id, status) WHERE purchase_order_id IS NOT NULL;
CREATE UNIQUE INDEX payments_provider_reference_unique
    ON payments (business_id, provider, provider_reference)
    WHERE provider IS NOT NULL AND provider_reference IS NOT NULL;

-- Returns and refunds -------------------------------------------------------

CREATE TABLE sales_returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    sale_id UUID NOT NULL,
    location_id UUID NOT NULL,
    return_number VARCHAR(60) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'approved', 'received', 'rejected', 'cancelled')),
    reason TEXT,
    created_by UUID NOT NULL,
    received_by UUID,
    received_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT sales_returns_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT sales_returns_number_unique UNIQUE (business_id, return_number),
    CONSTRAINT sales_returns_sale_same_business_fk
        FOREIGN KEY (business_id, sale_id) REFERENCES sales (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT sales_returns_location_same_business_fk
        FOREIGN KEY (business_id, location_id) REFERENCES locations (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT sales_returns_created_by_member_fk
        FOREIGN KEY (business_id, created_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT sales_returns_received_by_member_fk
        FOREIGN KEY (business_id, received_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT sales_returns_received_fields_check
        CHECK (status <> 'received' OR (received_by IS NOT NULL AND received_at IS NOT NULL))
);
CREATE INDEX sales_returns_sale_idx ON sales_returns (business_id, sale_id, created_at DESC);
CREATE INDEX sales_returns_status_idx ON sales_returns (business_id, status, created_at DESC);

CREATE TABLE sales_return_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    return_id UUID NOT NULL,
    sale_item_id UUID NOT NULL,
    quantity_returned NUMERIC(14, 3) NOT NULL CHECK (quantity_returned > 0),
    restock_quantity NUMERIC(14, 3) NOT NULL DEFAULT 0 CHECK (restock_quantity >= 0),
    item_condition VARCHAR(20) NOT NULL DEFAULT 'unknown'
        CHECK (item_condition IN ('sellable', 'damaged', 'defective', 'unknown')),
    refund_amount NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (refund_amount >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT sales_return_items_return_sale_item_unique UNIQUE (return_id, sale_item_id),
    CONSTRAINT sales_return_items_return_same_business_fk
        FOREIGN KEY (business_id, return_id) REFERENCES sales_returns (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT sales_return_items_sale_item_same_business_fk
        FOREIGN KEY (business_id, sale_item_id) REFERENCES sale_items (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT sales_return_items_restock_limit_check CHECK (restock_quantity <= quantity_returned),
    CONSTRAINT sales_return_items_condition_check
        CHECK (item_condition <> 'sellable' OR restock_quantity = quantity_returned)
);
CREATE INDEX sales_return_items_sale_item_idx ON sales_return_items (business_id, sale_item_id);

CREATE TABLE refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    payment_id UUID NOT NULL,
    sales_return_id UUID,
    amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processed', 'failed', 'cancelled')),
    provider_reference VARCHAR(160),
    reason TEXT,
    processed_by UUID,
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT refunds_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT refunds_payment_same_business_fk
        FOREIGN KEY (business_id, payment_id) REFERENCES payments (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT refunds_return_same_business_fk
        FOREIGN KEY (business_id, sales_return_id) REFERENCES sales_returns (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT refunds_processed_by_member_fk
        FOREIGN KEY (business_id, processed_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT,
    CONSTRAINT refunds_processed_fields_check
        CHECK (status <> 'processed' OR (processed_by IS NOT NULL AND processed_at IS NOT NULL))
);
CREATE INDEX refunds_payment_idx ON refunds (business_id, payment_id, status);
CREATE UNIQUE INDEX refunds_provider_reference_unique
    ON refunds (business_id, provider_reference)
    WHERE provider_reference IS NOT NULL;

-- Expenses -----------------------------------------------------------------

CREATE TABLE expense_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT expense_categories_business_id_id_unique UNIQUE (business_id, id)
);
CREATE UNIQUE INDEX expense_categories_business_name_unique
    ON expense_categories (business_id, LOWER(name));

CREATE TABLE expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    location_id UUID,
    category_id UUID,
    expense_number VARCHAR(60) NOT NULL,
    description VARCHAR(240) NOT NULL,
    amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    payment_method VARCHAR(30)
        CHECK (payment_method IS NULL OR payment_method IN ('cash', 'card', 'bank_transfer', 'mobile_money', 'other')),
    paid_to VARCHAR(180),
    status VARCHAR(20) NOT NULL DEFAULT 'recorded'
        CHECK (status IN ('recorded', 'voided')),
    incurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT expenses_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT expenses_number_unique UNIQUE (business_id, expense_number),
    CONSTRAINT expenses_location_same_business_fk
        FOREIGN KEY (business_id, location_id) REFERENCES locations (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT expenses_category_same_business_fk
        FOREIGN KEY (business_id, category_id) REFERENCES expense_categories (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT expenses_created_by_member_fk
        FOREIGN KEY (business_id, created_by) REFERENCES business_members (business_id, user_id) ON DELETE RESTRICT
);
CREATE INDEX expenses_business_date_idx ON expenses (business_id, incurred_at DESC);
CREATE INDEX expenses_category_idx ON expenses (business_id, category_id, incurred_at DESC);

-- Transactional outbox: the API writes an event here in the same PostgreSQL
-- transaction as the business change. A worker later copies it to MongoDB.
CREATE TABLE outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    aggregate_type VARCHAR(60) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL CHECK (JSONB_TYPEOF(payload) = 'object'),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'processed', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX outbox_events_pending_idx
    ON outbox_events (available_at, created_at)
    WHERE status IN ('pending', 'failed');
CREATE INDEX outbox_events_business_created_idx
    ON outbox_events (business_id, created_at DESC);

-- updated_at triggers -------------------------------------------------------

CREATE TRIGGER suppliers_set_updated_at
    BEFORE UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER customers_set_updated_at
    BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER purchase_orders_set_updated_at
    BEFORE UPDATE ON purchase_orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER purchase_receipts_set_updated_at
    BEFORE UPDATE ON purchase_receipts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER sales_set_updated_at
    BEFORE UPDATE ON sales FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER sales_returns_set_updated_at
    BEFORE UPDATE ON sales_returns FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER expenses_set_updated_at
    BEFORE UPDATE ON expenses FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
