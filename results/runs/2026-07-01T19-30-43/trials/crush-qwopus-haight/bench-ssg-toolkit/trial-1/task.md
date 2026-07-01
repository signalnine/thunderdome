# T9: SSG Toolkit

Add 8 plugins to an existing Static Site Generator toolkit.

## Starting State
- `src/core/` contains the build engine, types, and templates (~600 lines)
- 15 existing tests in `tests/core.test.ts` — these must continue to pass
- Plugin test files in `tests/plugins/` define the expected behavior

## Requirements

Build 8 plugins in `src/plugins/`, each implementing the `Plugin` interface from `src/core/types.ts`.

### Wave 1 (no dependencies)
1. **markdown-ext** — Markdown → HTML with footnotes and admonition containers
2. **asset-pipeline** — Rewrite asset URLs and generate manifest
3. **syntax-highlight** — Add language classes to code blocks
4. **taxonomy** — Build tag/category indices and generate tag pages

### Wave 2 (depend on Wave 1)
5. **rss-feed** — Generate RSS 2.0 feed (depends: markdown-ext, taxonomy)
6. **search-index** — Generate search index JSON (depends: markdown-ext, syntax-highlight)

### Wave 3 (depend on Wave 2)
7. **sitemap** — Generate sitemap XML (depends: taxonomy, rss-feed)
8. **dev-server** — Generate dev server config (depends: asset-pipeline, search-index)

### Plugin Interface
Each plugin must export a `createXxxPlugin()` factory function that returns a `Plugin` object.

## Validation
- `npm test` — all tests must pass (15 existing + 60 new)
- `npm run build` — must compile
- `npm run lint` — must be clean
