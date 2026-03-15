# T7: Plugin Marketplace

**Category:** greenfield/complex
**Timeout:** 30 minutes

## Objective

Build a plugin marketplace system that lets developers register plugins, resolve version dependencies, execute plugin code safely, collect user reviews, and manage dependency graphs.

The shared type definitions for all modules live in `src/types.ts` (read-only, do not modify). Your implementation must conform to these interfaces.

## Modules

You should build 5 capabilities:

1. **Plugin Registry** -- A catalog of plugin manifests. Users can add plugins, look them up by name, browse all plugins, search through them, and remove specific versions. A single plugin can have multiple registered versions.

2. **Version Resolver** -- Logic for resolving semver version constraints. Given a set of version constraints and the versions available in the registry, determine which concrete versions satisfy each constraint. Use the `semver` npm package (already in dependencies).

3. **Sandboxed Runner** -- Execute arbitrary plugin code strings in an isolated environment using Node.js `vm` module. Support passing context variables into the sandbox. Enforce execution timeouts so runaway code doesn't hang the system. Return structured results including success/failure, output, timing, and memory info.

4. **Review System** -- Let users leave ratings and comments on plugins. Support flagging inappropriate reviews and computing average ratings (flagged reviews should be excluded from averages). Allow querying reviews by plugin, by user, and by flagged status.

5. **Dependency Graph** -- Analyze plugin dependency relationships. Build dependency trees, detect circular dependencies, produce topological orderings, and flatten transitive dependency lists.

## Integration Layer

Export a `createMarketplace()` function from `src/index.ts` that composes all five capabilities and provides a high-level `installPlugin()` workflow. The install workflow should:

- Validate that the plugin manifest has the required fields (name, version, entryPoint)
- Register the plugin in the catalog
- Resolve its dependency versions against what's available in the registry
- Check for circular dependencies (reject if found)
- Execute the plugin's entry point in the sandbox
- Return the resolved dependency versions and sandbox execution result

## Constraints

- **DO NOT modify `src/types.ts`** -- it defines the shared interfaces for all modules
- Use `better-sqlite3` for any persistence needs (already in dependencies)
- Use `semver` package for version resolution (already in dependencies)
- Use Node.js `vm` module for sandboxing (NOT vm2)
- Modules should only share types, not import each other directly

## Provided Files

- `src/types.ts` -- Read-only shared type definitions
- `package.json` -- Dependencies already configured
- `tsconfig.json`, `.eslintrc.cjs`, `vitest.config.ts` -- Build/test config

## Validation

```bash
npm run build   # TypeScript compilation must succeed
npm run lint    # ESLint must pass
npm test        # Tests must pass
```

Tip: Write your own tests to verify behavior as you go.
