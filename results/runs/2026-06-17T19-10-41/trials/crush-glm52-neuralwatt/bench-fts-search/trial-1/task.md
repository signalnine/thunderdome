# T3: Full-Text Search Feature

## Category
features/medium

## Timeout
30 minutes

## Description
An existing Express + SQLite note-taking API has CRUD endpoints for notes (title, body, tags, timestamps) and tag-based filtering. Add full-text search using SQLite FTS5.

## Requirements

### 1. Search Endpoint: `GET /notes/search?q=<query>`
- Full-text search across note titles and bodies using SQLite FTS5
- Results ranked by relevance (BM25 ranking)
- Snippet highlighting with `<mark>` tags around matched terms
- Quoted phrase support (e.g., `?q="exact phrase"`)
- Pagination: 20 results per page, controlled by `?page=N` parameter
- Response format: `{ results: SearchResult[], total: number, page: number, perPage: number }`
- Returns 400 if `q` parameter is missing or empty

### 2. Suggest Endpoint: `GET /notes/search/suggest?q=<prefix>`
- Autocomplete that returns up to 5 matching note titles
- Matches prefix against note content (title and body)
- Response format: `{ results: SuggestResult[] }`
- Returns 400 if `q` parameter is missing or empty

### 3. FTS Index Synchronization
- FTS index must stay in sync when notes are created, updated, or deleted
- Use SQLite triggers or manual sync in the CRUD operations

## Interfaces (already defined in `src/models.ts`)

```ts
interface SearchResult {
  id: number;
  title: string;
  snippet: string;  // with <mark> highlighting
  rank: number;
}

interface SuggestResult {
  id: number;
  title: string;
}
```

## Existing Code
- `src/db.ts` - Database setup with `notes` table
- `src/models.ts` - TypeScript interfaces (SearchResult and SuggestResult already defined)
- `src/routes.ts` - CRUD routes for notes
- `src/errors.ts` - Error handling middleware
- `src/server.ts` - Express app setup
- `src/seed.ts` - Seed script with ~50 sample notes

## Tests
- `tests/notes.test.ts` - 15 existing CRUD tests (must continue passing)
- `tests/search.test.ts` - 20 search tests (must pass after implementation)

## Validation
```bash
npm test
```
All 35 tests must pass.
