# T2: Real-Time Collaborative Document Editor

## Category
greenfield/complex

## Timeout
30 minutes

## Description

Build a collaborative real-time document editing server. Multiple users should be able to open the same document and make edits simultaneously, with changes appearing in real time for everyone. Think Google Docs, but simplified.

The system needs:

1. **REST API for document management** -- Users need to create, read, update, list, and delete documents. Each document should have a title and content. Documents also need version history so users can see how a document evolved over time.

2. **WebSocket-based real-time collaboration** -- When a user opens a document, they connect via WebSocket and receive the current document state. As they type, their edits are sent as operations (insertions and deletions) and broadcast to other connected users viewing the same document.

3. **Conflict resolution** -- When two users edit simultaneously, their changes must not corrupt the document. Use Operational Transform (OT) or CRDTs to ensure all clients converge to the same document state. Both insertions must be preserved; nothing should be silently dropped.

4. **Persistence** -- Use SQLite (via better-sqlite3) to persist documents and their version history. Data should survive server restarts.

5. **Robustness** -- Handle at least 10 concurrent clients on the same document without corruption. Reject malformed or invalid operations gracefully (send error messages back, don't crash).

## Structural Requirement

Your server entry point must export a `createApp` factory function from `src/server.ts` (or `src/index.ts`). This function should accept an optional database file path and return an object with at least:

- `app` -- the HTTP server/application (e.g., Express app)
- `start(port?)` -- starts listening, returns the port number (use port 0 for a random available port)
- `stop()` -- cleanly shuts down the server and all connections

## Tech Stack

- TypeScript (the project is already configured with tsconfig.json)
- Express for HTTP
- ws for WebSocket
- better-sqlite3 for SQLite
- All dependencies are pre-installed

## What Success Looks Like

- `npm run build` compiles without errors
- `npm run lint` passes
- The server handles the full lifecycle: create doc via REST, connect via WebSocket, send edits, receive broadcasts, verify convergence via REST
- Documents persist across server restarts
- Concurrent edits from multiple clients converge to consistent state

## Tips

- The WebSocket connection path should include the document ID so the server knows which document the client wants to collaborate on
- Send a sync message with the current document content when a client first connects
- Track document versions so you can transform concurrent operations correctly
- Write tests for your implementation -- they'll help you catch edge cases
