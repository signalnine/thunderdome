# T1: CLI Time Tracker

**Category:** greenfield/simple
**Timeout:** 15 minutes

## Objective

Build a time tracking library in TypeScript. All source code goes in `src/`.

## Requirements

Build a library that lets users track how they spend their time. It should support:

- **Starting and stopping timers** — A user can start a named timer and stop it later. Starting a new timer while one is already running should automatically stop the previous one.
- **Recording time entries** — Each entry should capture the task name, when it started, and when it stopped (if it has been stopped).
- **Persistence** — Data must be saved to a JSON file so it survives between sessions. The file path should be configurable. The file and any parent directories should be created automatically if they don't exist.
- **Querying entries** — Users should be able to retrieve all entries, or filter entries by date range.
- **Summarizing time** — Users should be able to get a summary of total time spent per task name (in milliseconds). Multiple entries with the same task name should be summed together. Running tasks should use the current time for their duration.
- **Error handling** — Starting a timer with an empty name should throw an error. Stopping when nothing is running should throw an error.
- **Unicode support** — Task names with unicode characters and emoji should work correctly.

Export your public API from `src/index.ts`.

## Validation

Run `npm run build` to verify TypeScript compilation.

Run `npm run lint` to verify code quality.

## Constraints

- All code must be in `src/` directory
- Must compile with the provided `tsconfig.json` (strict mode, ES2022, Node16 modules)
- Must pass the provided ESLint configuration
- No additional runtime dependencies may be added (use only Node.js built-in modules)
- You are encouraged to write your own tests
