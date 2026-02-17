# T2: Real-Time Markdown Collab Server

## Category
greenfield/complex

## Timeout
30 minutes

## Description
Build a WebSocket-based collaborative Markdown editing system with:
1. HTTP/WebSocket server managing documents and broadcasting edits
2. OT (Operational Transform) based conflict resolution so simultaneous edits converge
3. REST API for document CRUD with SQLite persistence via better-sqlite3
4. Version history - every edit stored, any past version retrievable
5. Must handle 10 concurrent clients without corruption

## Starting State
- All configuration files provided (package.json, tsconfig.json, .eslintrc.cjs, vitest.config.ts)
- Database schema provided (schema.sql)
- Test file provided (tests/collab.test.ts) with 45 tests
- Empty src/ directory with .gitkeep

## Requirements

### Source Files to Implement

**src/db.ts** - Database setup using schema.sql, connection factory

**src/models.ts** - TypeScript interfaces for Document, Version, Operation (insert/delete with position)

**src/ot.ts** - Operational Transform logic:
- `applyOperation(content, op)`: Apply an operation to document content
- `transformOperation(op1, op2)`: Transform op1 against op2
- `validateOperation(op, contentLength)`: Validate operation bounds
- Operations: `{ type: 'insert', position: number, text: string }` and `{ type: 'delete', position: number, count: number }`
- Transform rules: adjust positions based on prior operations

**src/routes.ts** - Express REST routes:
- POST /docs - Create document
- GET /docs - List documents
- GET /docs/:id - Get document
- PUT /docs/:id - Update document
- DELETE /docs/:id - Delete document
- GET /docs/:id/versions - List version history
- GET /docs/:id/versions/:version - Get specific version

**src/ws.ts** - WebSocket server:
- Manages rooms (one per document)
- On connect: validate document exists, send current state as `{ type: 'sync', content, version }`
- On operation: validate, apply, transform against concurrent ops, broadcast to room
- Track document version for OT
- Messages: `{ type: 'operation'|'ack'|'sync'|'error', ... }`

**src/server.ts** - Combines Express + WebSocket server:
- Exports `createApp(dbPath?)` returning `{ app, server, wss, db, start, stop }`
- HTTP and WS on the same port
- `start(port?)` returns actual port (use port 0 for random)
- `stop()` cleanly shuts down all connections

## Validation
```bash
npm run build   # TypeScript compiles
npm run lint    # ESLint passes
npm test        # All 45 tests pass
```
