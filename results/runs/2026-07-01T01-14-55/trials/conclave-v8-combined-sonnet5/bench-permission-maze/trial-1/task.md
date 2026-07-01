# T15: Permission Maze

**Category:** greenfield/complex
**Timeout:** 30 minutes

## Objective

Build a document management API using Express and Node.js. The system manages users, hierarchical folders, documents, and granular sharing permissions. All storage should be in-memory (no database required).

## Core Features

### 1. User Management

- **Register** a new user with username and password
- **Login** to receive an authentication token
- Token-based auth: all subsequent requests include the token (via `Authorization: Bearer <token>` header)

### 2. Folders

- Create, read, update, delete folders
- Folders can be nested inside other folders (hierarchical structure)
- Each folder has a name and an optional parent folder

### 3. Documents

- Create, read, update, delete documents inside folders
- Each document has a title, content (text), and belongs to a folder
- The creator of a document is its owner

### 4. Sharing & Permissions

Three roles: **viewer**, **editor**, **owner**

- **Viewer**: can read the resource
- **Editor**: can read and modify the resource, and share it with others
- **Owner**: full control including deletion and role management

Share folders or documents with other users by assigning them a role. The creator of a resource is automatically its owner.

When a user has access to a resource through multiple paths (e.g., direct share + folder share), their effective permission should reflect the most permissive role granted.

### 5. Activity Log

Track actions performed in the system:
- Document creation, updates, deletion
- Sharing events
- Each log entry records the action type, the user who performed it, the target resource, and a timestamp

## API Design

Build a RESTful API. You choose the exact route structure, but it should be intuitive and consistent. Common patterns:

- `POST /users` or `POST /auth/register` -- register
- `POST /auth/login` or `POST /login` -- login
- `POST /folders` -- create folder
- `GET /folders/:id` -- get folder
- `POST /documents` or `POST /folders/:folderId/documents` -- create document
- `GET /documents/:id` -- get document
- `POST /share` or `POST /:resourceType/:id/share` -- share resource
- `GET /activity` -- get activity log

Return appropriate HTTP status codes (200, 201, 204, 400, 404, etc.).

## Technical Requirements

- Use Express.js
- In-memory storage (Maps, arrays, plain objects -- your choice)
- Export a `createApp()` function from your main module (`src/index.ts`, `src/app.ts`, or `src/server.ts`) that returns the Express app instance
- TypeScript
- All data resets when the server restarts (no persistence needed)

## Provided Files

- `package.json` -- dependencies configured
- `tsconfig.json`, `.eslintrc.cjs`, `vitest.config.ts` -- build/test config

## Validation

```bash
npm run build   # TypeScript compilation must succeed
npm run lint    # ESLint must pass
npm test        # Tests must pass
```

Write your own tests to verify behavior as you build.
