-- Inventory & Sales Management System
-- Migration 001: business accounts, users, locations and product catalogue
-- PostgreSQL 13+ recommended

BEGIN;

-- gen_random_uuid() is built into PostgreSQL 13+.

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TABLE businesses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    slug VARCHAR(100) NOT NULL,
    business_type VARCHAR(50) NOT NULL DEFAULT 'general',
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    timezone VARCHAR(64) NOT NULL DEFAULT 'Africa/Lagos',
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX businesses_slug_unique_ci
    ON businesses (LOWER(slug));

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'disabled')),
    email_verified_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX users_email_unique_ci
    ON users (LOWER(email));

CREATE TABLE business_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    role VARCHAR(30) NOT NULL
        CHECK (role IN ('owner', 'manager', 'sales_attendant')),
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('invited', 'active', 'suspended', 'removed')),
    joined_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT business_members_business_user_unique UNIQUE (business_id, user_id)
);

CREATE INDEX business_members_user_id_idx ON business_members (user_id);
CREATE INDEX business_members_business_role_idx ON business_members (business_id, role);

CREATE TABLE invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    email VARCHAR(255) NOT NULL,
    role VARCHAR(30) NOT NULL
        CHECK (role IN ('manager', 'sales_attendant')),
    token_hash TEXT NOT NULL UNIQUE,
    invited_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX invitations_business_status_idx ON invitations (business_id, status);
CREATE INDEX invitations_email_ci_idx ON invitations (LOWER(email));

CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    name VARCHAR(120) NOT NULL,
    code VARCHAR(40),
    type VARCHAR(20) NOT NULL DEFAULT 'store'
        CHECK (type IN ('store', 'warehouse')),
    address_line_1 VARCHAR(200),
    address_line_2 VARCHAR(200),
    city VARCHAR(100),
    state VARCHAR(100),
    country_code CHAR(2) NOT NULL DEFAULT 'NG',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT locations_business_id_id_unique UNIQUE (business_id, id)
);

CREATE UNIQUE INDEX locations_business_code_unique
    ON locations (business_id, LOWER(code))
    WHERE code IS NOT NULL;
CREATE INDEX locations_business_active_idx ON locations (business_id, is_active);

CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    parent_id UUID,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT categories_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT categories_parent_same_business_fk
        FOREIGN KEY (business_id, parent_id)
        REFERENCES categories (business_id, id)
        ON DELETE RESTRICT
);

CREATE UNIQUE INDEX categories_business_name_unique
    ON categories (business_id, LOWER(name));
CREATE INDEX categories_parent_id_idx ON categories (business_id, parent_id);

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    category_id UUID,
    name VARCHAR(180) NOT NULL,
    description TEXT,
    brand VARCHAR(100),
    unit_of_measure VARCHAR(30) NOT NULL DEFAULT 'unit',
    track_inventory BOOLEAN NOT NULL DEFAULT TRUE,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT products_business_id_id_unique UNIQUE (business_id, id),
    CONSTRAINT products_category_same_business_fk
        FOREIGN KEY (business_id, category_id)
        REFERENCES categories (business_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX products_business_status_idx ON products (business_id, status);
CREATE INDEX products_business_category_idx ON products (business_id, category_id);
CREATE INDEX products_business_name_idx ON products (business_id, LOWER(name));

CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL,
    variant_name VARCHAR(120) NOT NULL DEFAULT 'Default',
    sku VARCHAR(80) NOT NULL,
    barcode VARCHAR(100),
    attributes JSONB NOT NULL DEFAULT '{}'::JSONB
        CHECK (JSONB_TYPEOF(attributes) = 'object'),
    cost_price NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (cost_price >= 0),
    selling_price NUMERIC(14, 2) NOT NULL CHECK (selling_price >= 0),
    reorder_level INTEGER NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT product_variants_product_same_business_fk
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id)
        ON DELETE RESTRICT,
    CONSTRAINT product_variants_business_id_id_unique UNIQUE (business_id, id)
);

CREATE UNIQUE INDEX product_variants_business_sku_unique
    ON product_variants (business_id, LOWER(sku));
CREATE UNIQUE INDEX product_variants_business_barcode_unique
    ON product_variants (business_id, barcode)
    WHERE barcode IS NOT NULL;
CREATE INDEX product_variants_product_id_idx ON product_variants (business_id, product_id);

CREATE TABLE product_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL,
    object_key TEXT NOT NULL UNIQUE,
    alt_text VARCHAR(200),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT product_images_product_same_business_fk
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id)
        ON DELETE RESTRICT
);

CREATE UNIQUE INDEX product_images_one_primary_per_product
    ON product_images (business_id, product_id)
    WHERE is_primary = TRUE;
CREATE INDEX product_images_product_sort_idx
    ON product_images (business_id, product_id, sort_order);

-- Keep updated_at accurate even when updates happen outside the application.
CREATE TRIGGER businesses_set_updated_at
    BEFORE UPDATE ON businesses
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER business_members_set_updated_at
    BEFORE UPDATE ON business_members
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER locations_set_updated_at
    BEFORE UPDATE ON locations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER categories_set_updated_at
    BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER products_set_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER product_variants_set_updated_at
    BEFORE UPDATE ON product_variants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
