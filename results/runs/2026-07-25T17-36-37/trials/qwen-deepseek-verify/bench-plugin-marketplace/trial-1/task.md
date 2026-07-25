# T7: Plugin Marketplace

**Category:** greenfield/complex
**Timeout:** 30 minutes
**Tests:** 55 total (40 unit + 15 integration)

## Objective

Build a plugin marketplace with 5 independent modules. Each module has its own directory, its own tests, and zero cross-module imports. A shared read-only `src/types.ts` defines all inter-module contracts. A thin integration layer `src/index.ts` composes the modules.

## Modules

1. **Plugin Registry** (`src/registry/index.ts`) — CRUD for plugin metadata with SQLite (better-sqlite3). Stores plugin manifests with name+version as composite key. Search by name/description substring.

2. **Version Resolver** (`src/resolver/index.ts`) — Semver constraint resolution using the `semver` npm package. Resolves a set of version constraints against available versions. Pure logic, no database.

3. **Sandboxed Runner** (`src/runner/index.ts`) — Execute plugin code in isolated contexts using Node.js `vm` module. Supports timeout enforcement and memory tracking. Returns structured SandboxResult.

4. **Review System** (`src/reviews/index.ts`) — Ratings, comments, and moderation flags with SQLite. Computes average ratings (excluding flagged reviews). Supports querying by user, plugin, and flagged status.

5. **Dependency Graph** (`src/deps/index.ts`) — Topological sort, cycle detection using DFS, dependency tree building, and flattening. Pure logic that queries the registry.

## Integration Layer

`src/index.ts` exports a `createMarketplace()` function that composes all 5 modules and provides an `installPlugin()` workflow:
- Validate manifest (name, version, entryPoint required)
- Register the plugin
- Resolve dependency versions from registry
- Check for circular dependencies
- Execute entry point in sandbox
- Return resolved versions and sandbox result

## Constraints

- **DO NOT modify `src/types.ts`** — its SHA-256 checksum is validated in integration tests
- Each module must implement its corresponding service interface from `types.ts`
- Modules import types from `../types.js` (ESM with .js extension)
- Use `better-sqlite3` for database modules (registry, reviews)
- Use `semver` package for version resolution
- Use Node.js `vm` module (NOT vm2) for sandboxing
- Zero cross-module imports (modules only depend on types)

## Provided Files

- `src/types.ts` — Read-only shared type definitions (~90 lines)
- `package.json` — Dependencies already configured
- `tsconfig.json`, `.eslintrc.cjs`, `vitest.config.ts` — Build/test config
- All test files in `tests/`

## Validation

```bash
npm run build   # TypeScript compilation must succeed
npm run lint    # ESLint must pass
npm test        # All 55 tests must pass
```
