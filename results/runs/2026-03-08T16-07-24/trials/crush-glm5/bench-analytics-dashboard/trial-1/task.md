# T8: Analytics Dashboard

Build a multi-tenant analytics dashboard API.

## Starting State
- `schema.sql` defines the database tables
- Tests are in `tests/`
- Empty `src/` directory

## Requirements
Each feature can be built independently:

### 1. User Management (`src/users/`)
- POST /users - Register new user (email, password, tenant_id)
- POST /users/login - Login, returns JWT token
- GET /users/me - Get current user profile
- PATCH /users/:id/role - Change user role (admin only)

### 2. Data Ingestion (`src/ingest/`)
- POST /events - Ingest a single event
- POST /events/batch - Ingest multiple events

### 3. Query Engine (`src/query/`)
- POST /query/count - Count events matching filter
- POST /query/timeseries - Time-bucketed event counts
- POST /query/breakdown - Event counts grouped by property
- POST /query/funnel - Multi-step funnel analysis

### 4. Dashboard Configuration (`src/dashboards/`)
- Full CRUD for dashboards and widgets
- Widgets: counter, timeseries, breakdown, funnel types

### 5. Data Export (`src/export/`)
- GET /export/events?format=csv|json - Export events
- GET /export/dashboard/:id - Export dashboard data

## Validation
- `npm test` — all tests must pass
- `npm run build` — must compile
- `npm run lint` — must be clean
