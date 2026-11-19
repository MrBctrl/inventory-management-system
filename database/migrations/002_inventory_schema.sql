-- Inventory & Sales Management System
-- Migration 002: stock balances, movements, transfers and adjustments
-- Requires migration 001_core_schema.sql to have been applied.

BEGIN;

-- One row represents one variant at one business location.
-- The composite primary key prevents duplicate balances for the same location/variant.
CREATE TABLE inventory_balances (
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    location_id UUID NOT NULL,
    variant_id UUID NOT NULL,
    quantity_on_hand NUMERIC(14, 3) NOT NULL DEFAULT 0
        CHECK (quantity_on_hand >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (business_id, location_id, variant_id),
    CONSTRAINT inventory_balances_location_same_business_fk
        FOREIGN KEY (business_id, location_id)
        REFERENCES locations (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT inventory_balances_variant_same_business_fk
        FOREIGN KEY (business_id, variant_id)
        REFERENCES product_variants (business_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX inventory_balances_business_variant_idx
    ON inventory_balances (business_id, variant_id);

-- Append-only ledger. quantity_delta is positive for stock coming in
-- and negative for stock going out.
CREATE TABLE inventory_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    location_id UUID NOT NULL,
    variant_id UUID NOT NULL,
    movement_type VARCHAR(30) NOT NULL
        CHECK (movement_type IN (
            'opening_balance',
            'purchase_receipt',
            'sale',
            'sale_return',
            'transfer_in',
            'transfer_out',
            'adjustment',
            'void_reversal'
        )),
    quantity_delta NUMERIC(14, 3) NOT NULL CHECK (quantity_delta <> 0),
    unit_cost NUMERIC(14, 2) CHECK (unit_cost IS NULL OR unit_cost >= 0),
    reference_type VARCHAR(40),
    reference_id UUID,
    notes TEXT,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT inventory_movements_location_same_business_fk
        FOREIGN KEY (business_id, location_id)
        REFERENCES locations (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT inventory_movements_variant_same_business_fk
        FOREIGN KEY (business_id, variant_id)
        REFERENCES product_variants (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT inventory_movements_actor_same_business_fk
        FOREIGN KEY (business_id, created_by)
        REFERENCES business_members (business_id, user_id)
        ON DELETE RESTRICT,
    CONSTRAINT inventory_movements_reference_pair_check
        CHECK (
            (reference_type IS NULL AND reference_id IS NULL)
            OR (reference_type IS NOT NULL AND reference_id IS NOT NULL)
        ),
    CONSTRAINT inventory_movements_direction_check
        CHECK (
            (movement_type IN ('opening_balance', 'purchase_receipt', 'sale_return', 'transfer_in')
                AND quantity_delta > 0)
            OR (movement_type IN ('sale', 'transfer_out') AND quantity_delta < 0)
            OR (movement_type IN ('adjustment', 'void_reversal'))
        )
);

CREATE INDEX inventory_movements_variant_history_idx
    ON inventory_movements (business_id, location_id, variant_id, created_at DESC);
CREATE INDEX inventory_movements_reference_idx
    ON inventory_movements (business_id, reference_type, reference_id)
    WHERE reference_id IS NOT NULL;
CREATE INDEX inventory_movements_business_created_idx
    ON inventory_movements (business_id, created_at DESC);

-- Transfers are completed atomically in the first release:
-- source stock decreases and destination stock increases in one database transaction.
CREATE TABLE stock_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    transfer_number VARCHAR(50) NOT NULL,
    source_location_id UUID NOT NULL,
    destination_location_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'completed', 'cancelled')),
    notes TEXT,
    created_by UUID NOT NULL,
    completed_by UUID,
    completed_at TIMESTAMPTZ,
    cancelled_by UUID,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stock_transfers_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT stock_transfers_number_unique UNIQUE (business_id, transfer_number),
    CONSTRAINT stock_transfers_different_locations_check
        CHECK (source_location_id <> destination_location_id),
    CONSTRAINT stock_transfers_source_same_business_fk
        FOREIGN KEY (business_id, source_location_id)
        REFERENCES locations (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_transfers_destination_same_business_fk
        FOREIGN KEY (business_id, destination_location_id)
        REFERENCES locations (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_transfers_created_by_member_fk
        FOREIGN KEY (business_id, created_by)
        REFERENCES business_members (business_id, user_id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_transfers_completed_by_member_fk
        FOREIGN KEY (business_id, completed_by)
        REFERENCES business_members (business_id, user_id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_transfers_cancelled_by_member_fk
        FOREIGN KEY (business_id, cancelled_by)
        REFERENCES business_members (business_id, user_id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_transfers_completion_fields_check
        CHECK (
            (status <> 'completed' OR (completed_by IS NOT NULL AND completed_at IS NOT NULL))
        ),
    CONSTRAINT stock_transfers_cancellation_fields_check
        CHECK (
            (status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL))
        )
);

CREATE INDEX stock_transfers_business_status_idx
    ON stock_transfers (business_id, status, created_at DESC);
CREATE INDEX stock_transfers_source_location_idx
    ON stock_transfers (business_id, source_location_id, created_at DESC);
CREATE INDEX stock_transfers_destination_location_idx
    ON stock_transfers (business_id, destination_location_id, created_at DESC);

CREATE TABLE stock_transfer_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    transfer_id UUID NOT NULL,
    variant_id UUID NOT NULL,
    quantity NUMERIC(14, 3) NOT NULL CHECK (quantity > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stock_transfer_items_transfer_variant_unique UNIQUE (transfer_id, variant_id),
    CONSTRAINT stock_transfer_items_transfer_same_business_fk
        FOREIGN KEY (business_id, transfer_id)
        REFERENCES stock_transfers (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_transfer_items_variant_same_business_fk
        FOREIGN KEY (business_id, variant_id)
        REFERENCES product_variants (business_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX stock_transfer_items_variant_idx
    ON stock_transfer_items (business_id, variant_id);

-- An adjustment captures a physical count. Posting it later records the
-- difference between the current balance and the approved counted quantity.
CREATE TABLE stock_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    adjustment_number VARCHAR(50) NOT NULL,
    location_id UUID NOT NULL,
    reason VARCHAR(30) NOT NULL
        CHECK (reason IN ('count_correction', 'damaged', 'lost', 'found', 'opening_stock', 'other')),
    status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'posted', 'cancelled')),
    notes TEXT,
    created_by UUID NOT NULL,
    posted_by UUID,
    posted_at TIMESTAMPTZ,
    cancelled_by UUID,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stock_adjustments_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT stock_adjustments_number_unique UNIQUE (business_id, adjustment_number),
    CONSTRAINT stock_adjustments_location_same_business_fk
        FOREIGN KEY (business_id, location_id)
        REFERENCES locations (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_adjustments_created_by_member_fk
        FOREIGN KEY (business_id, created_by)
        REFERENCES business_members (business_id, user_id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_adjustments_posted_by_member_fk
        FOREIGN KEY (business_id, posted_by)
        REFERENCES business_members (business_id, user_id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_adjustments_cancelled_by_member_fk
        FOREIGN KEY (business_id, cancelled_by)
        REFERENCES business_members (business_id, user_id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_adjustments_posting_fields_check
        CHECK (status <> 'posted' OR (posted_by IS NOT NULL AND posted_at IS NOT NULL)),
    CONSTRAINT stock_adjustments_cancellation_fields_check
        CHECK (status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL))
);

CREATE INDEX stock_adjustments_business_status_idx
    ON stock_adjustments (business_id, status, created_at DESC);
CREATE INDEX stock_adjustments_location_idx
    ON stock_adjustments (business_id, location_id, created_at DESC);

CREATE TABLE stock_adjustment_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    adjustment_id UUID NOT NULL,
    variant_id UUID NOT NULL,
    system_quantity_at_count NUMERIC(14, 3) NOT NULL
        CHECK (system_quantity_at_count >= 0),
    counted_quantity NUMERIC(14, 3) NOT NULL CHECK (counted_quantity >= 0),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stock_adjustment_items_adjustment_variant_unique
        UNIQUE (adjustment_id, variant_id),
    CONSTRAINT stock_adjustment_items_adjustment_same_business_fk
        FOREIGN KEY (business_id, adjustment_id)
        REFERENCES stock_adjustments (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT stock_adjustment_items_variant_same_business_fk
        FOREIGN KEY (business_id, variant_id)
        REFERENCES product_variants (business_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX stock_adjustment_items_variant_idx
    ON stock_adjustment_items (business_id, variant_id);

-- Keep updated_at accurate for mutable inventory records.
CREATE TRIGGER inventory_balances_set_updated_at
    BEFORE UPDATE ON inventory_balances
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER stock_transfers_set_updated_at
    BEFORE UPDATE ON stock_transfers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER stock_adjustments_set_updated_at
    BEFORE UPDATE ON stock_adjustments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Inventory movements are historical ledger entries and must not be rewritten.
CREATE OR REPLACE FUNCTION prevent_inventory_movement_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Inventory movements are immutable; create a reversal or adjustment instead.';
END;
$$;

CREATE TRIGGER inventory_movements_immutable
    BEFORE UPDATE OR DELETE ON inventory_movements
    FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();

COMMIT;
