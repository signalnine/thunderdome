# T1: CLI Time Tracker

**Category:** greenfield/simple
**Timeout:** 10 minutes
**Tests:** 25

## Objective

Build a command-line time tracking tool as a TypeScript library. All source code goes in `src/`.

## Requirements

Implement a `TimeTracker` class in `src/index.ts` that is exported (along with an `Entry` interface) with the following API:

### Entry Interface

```typescript
interface Entry {
  taskName: string;   // Name of the tracked task
  startTime: string;  // ISO 8601 timestamp
  endTime: string | null; // ISO 8601 timestamp, or null if still running
}
```

### TimeTracker Class

```typescript
class TimeTracker {
  constructor(filePath: string)
  start(taskName: string): Entry
  stop(): Entry
  getActiveTask(): Entry | null
  getLog(options?: { since?: Date }): Entry[]
  getSummary(): Record<string, number>
}
```

### Behavior

1. **constructor(filePath)** - Creates a tracker that persists data to the given JSON file path. The file and any parent directories should be created automatically when data is first written.

2. **start(taskName)** - Starts tracking a new task. Returns the created entry.
   - If a task is already running, it must be auto-stopped before the new one starts.
   - Throws an error if `taskName` is empty.
   - Unicode task names must be supported.

3. **stop()** - Stops the currently running task. Returns the stopped entry.
   - Throws an error if no task is currently running.

4. **getActiveTask()** - Returns the currently running entry, or `null` if nothing is active.

5. **getLog(options?)** - Returns all tracked entries.
   - If `options.since` is provided, filters to entries that:
     - Started on or after the `since` date, OR
     - Are still running (endTime is null), OR
     - Have an endTime on or after the `since` date (spanning the boundary)

6. **getSummary()** - Returns an object keyed by task name with total duration in milliseconds.
   - Multiple entries with the same task name have their durations summed.
   - For running tasks (no endTime), use the current time to calculate duration.
   - Returns an empty object if there are no entries.

### Persistence

- Data is stored as JSON in the file specified by the constructor.
- Creating a new `TimeTracker` instance with the same file path must load existing data.
- The file and parent directories are created on first write if they don't exist.

## Validation

Run `npm test` to execute the test suite. All 25 tests must pass.

Run `npm run build` to verify TypeScript compilation.

Run `npm run lint` to verify code quality.

## Constraints

- All code must be in `src/` directory
- Must compile with the provided `tsconfig.json` (strict mode, ES2022, Node16 modules)
- Must pass the provided ESLint configuration
- No additional dependencies may be added (use only Node.js built-in modules)
