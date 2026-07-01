# Versioned Document Store with Structural Merge

Build an in-memory versioned document store -- think "Git for JSON documents." The library should support CRUD operations on JSON documents, version history, branching, and three-way structural merging between branches.

## API

Export a `DocumentStore` class (or factory function) from `src/index.ts` with the following interface:

```typescript
interface DocumentStore {
  // Document CRUD
  create(id: string, content: object): void;
  get(id: string): object;
  update(id: string, content: object): void;
  delete(id: string): void;

  // Version history
  getHistory(id: string): Version[];
  getVersion(id: string, versionId: string): object;

  // Branching
  createBranch(name: string, fromBranch?: string): void;
  switchBranch(name: string): void;
  getBranch(): string;
  listBranches(): string[];

  // Merging
  merge(sourceBranch: string): MergeResult;
}

interface Version {
  id: string;
  timestamp: number;
  content: object;
}

interface MergeResult {
  merged: Record<string, object>;  // documentId -> merged content
  conflicts: Conflict[];
  applied: boolean;  // true if merge was auto-applied (no conflicts)
}

interface Conflict {
  documentId: string;
  path: string;       // dot-separated JSON path, e.g. "a.b.c"
  base: any;
  ours: any;
  theirs: any;
}
```

## Behavior

### Documents
- `create(id, content)` stores a new document. Throws if the ID already exists on the current branch.
- `get(id)` returns the current content. Throws if the document doesn't exist or has been deleted.
- `update(id, content)` replaces the document content and creates a new version. Throws if the document doesn't exist.
- `delete(id)` removes a document from the current branch. Throws if it doesn't exist.

### Version History
- Every `create` and `update` generates a new version with a unique `id`, a `timestamp`, and the full document `content` at that point.
- `getHistory(id)` returns versions in chronological order (oldest first).
- `getVersion(id, versionId)` returns the content at a specific version.

### Branching
- The default branch is `"main"`.
- `createBranch(name)` creates a new branch from the current branch's current state. If `fromBranch` is provided, branch from that branch instead.
- `switchBranch(name)` switches the active branch. All subsequent CRUD operations apply to that branch.
- Changes on one branch are not visible on other branches.

### Merging
- `merge(sourceBranch)` merges changes from `sourceBranch` into the current branch.
- Uses **three-way merge**: find the common ancestor state (the point where the branches diverged), then compare both branches against that base.
- For each document that changed on either branch:
  - If only one side changed a field, take that change (no conflict).
  - If both sides changed the same field to the **same** value, no conflict.
  - If both sides changed the same field to **different** values, that's a conflict.
- If there are **no conflicts**, the merge is auto-applied to the current branch (`applied: true`), and the `merged` field contains the resulting document contents.
- If there **are conflicts**, the merge is **not** applied (`applied: false`), and the conflicts are returned so the caller can resolve them. The current branch remains unchanged.
- The `merged` field always contains the merge result (with conflicts resolved in favor of "ours" for the purpose of showing what it would look like).
- A merge with no changes on either side is a no-op (fast-forward).

## Constraints
- All operations are synchronous and in-memory.
- Documents are plain JSON objects (no arrays at the top level, though fields may contain arrays).
- Deep clone document contents on storage and retrieval to prevent mutation.
- The store must handle multiple documents independently -- changes to different documents on different branches should merge cleanly with no conflicts.

## Project Structure

Put your implementation in `src/`. The entry point is `src/index.ts`. You may split into multiple files if you wish.
