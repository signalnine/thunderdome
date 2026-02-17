# T6: Monorepo Disaster

## Category
Recovery

## Timeout
30 minutes

## Description

A three-package TypeScript monorepo (npm workspaces) is broken after a botched merge and a half-finished refactor. The monorepo contains:

- **@monorepo/core** - Shared business logic (user management, validation, database)
- **@monorepo/api** - Express REST API that depends on core
- **@monorepo/worker** - Background job processor that depends on core

The previous developer attempted a refactor, merged incompletely, and left the repo in a broken state. Your job is to fix all issues so that:

1. `npm run build` succeeds (TypeScript compilation)
2. `npm run lint` passes (ESLint)
3. `npm test` passes (all tests, including structural validations)

## Known Issues

There are **6 breakages** that need to be fixed:

1. **Circular dependency** in `packages/core` - modules import each other in a cycle
2. **Half-renamed function** - `createUser` was renamed to `registerUser` but some call sites still use the old name
3. **Broken tsconfig project references** - the root `tsconfig.json` has packages in wrong build order
4. **Dependency version conflict** - a package has a pinned version that's too old for the APIs used in code
5. **Merge conflict markers** - a test file has unresolved merge conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
6. **Committed secrets** - a `.env` file with database credentials is checked into the repo

## Success Criteria

- `npm run build` exits 0
- `npm run lint` exits 0
- `npm test` passes all tests (35+ unit tests + 5 structural validations)
- No circular dependencies detected by madge
- No merge conflict markers in any `.ts` file
- No `.env` files containing passwords/secrets
- TypeScript strict mode enabled in all packages
