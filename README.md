# Inventory & Sales Management System

Backend starter for a multi-business inventory and sales management application.

## Requirements
- Node.js 20+
- PostgreSQL
- MongoDB Community Server

## Local setup

1. Create the PostgreSQL database `inventory_management_dev`.
2. Run migrations in order from `database/migrations/`:
   - `001_core_schema.sql`
   - `002_inventory_schema.sql`
   - `003_commerce_schema.sql`
3. Copy `.env.example` to `.env` and set your local PostgreSQL password.
4. Install dependencies and start the API:

```bash
npm install
npm run dev
```

5. Test:
   - `http://localhost:4000/`
   - `http://localhost:4000/api/health`

The health endpoint checks PostgreSQL and MongoDB. The API will not start unless both database connections succeed.

## Database responsibilities
- PostgreSQL is authoritative for business, inventory, purchasing, sales and financial records.
- MongoDB stores supporting flexible documents and event payloads.
- Do not store credentials in source control. `.env` is ignored by Git.

## Current API endpoints
- `GET /` - API welcome/availability response
- `GET /api/health` - API and database health checks
