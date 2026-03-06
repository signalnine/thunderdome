# T8: Analytics Dashboard

**Category:** greenfield/complex
**Timeout:** 30 minutes

## Objective

Build a multi-tenant analytics dashboard API in TypeScript. All source code goes in `src/`.

## Requirements

Build an HTTP API that allows multiple organizations (tenants) to independently collect, query, and visualize event data. The system should support five core capabilities:

### 1. User Management
Users need to register accounts, log in, and receive authentication tokens. Each user belongs to a tenant (organization). The system should support different roles (e.g., admin, editor, viewer). Admins should be able to change other users' roles within their tenant. Authenticated users should be able to view their own profile.

### 2. Data Ingestion
Authenticated users should be able to send analytics events into the system. Each event has a name, optional properties (arbitrary key-value pairs), and a timestamp. The system should support ingesting single events and batches of events efficiently. Events are automatically associated with the user's tenant.

### 3. Query Engine
Users need to analyze their collected event data. The query engine should support at least:
- **Counting** events that match a filter (e.g., count all "page_view" events)
- **Timeseries** queries that bucket event counts over time (e.g., daily page views)
- **Breakdowns** that group event counts by a property value (e.g., page views by URL)

All queries must respect tenant isolation -- users should only ever see their own tenant's data.

### 4. Dashboard Configuration
Users should be able to create, read, update, and delete dashboards. Dashboards are named collections that belong to a tenant. Dashboards are scoped to the tenant that created them.

### 5. Data Export
Users should be able to export their event data in both CSV and JSON formats. Dashboard data should also be exportable. Exports must respect tenant boundaries.

## Technical Requirements

- Use SQLite for persistence (a `schema.sql` file is provided with the database schema)
- Use JWT tokens for authentication
- All routes that access tenant data must require authentication
- Export a `createApp` function from `src/index.ts` (or `src/app.ts`) that returns an Express application instance
- Unauthenticated requests to protected routes should receive a 401 status

## Validation

Run `npm run build` to verify TypeScript compilation.

Run `npm run lint` to verify code quality.

You are encouraged to write your own tests to verify your implementation.

## Constraints

- All code must be in the `src/` directory
- Must compile with the provided `tsconfig.json` (strict mode, ES2022, Node16 modules)
- Must pass the provided ESLint configuration
- Use the provided `schema.sql` for database table definitions
- Dependencies are already listed in `package.json` -- use `express`, `better-sqlite3`, `jsonwebtoken`, and `uuid`
