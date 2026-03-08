# T5: Task Queue System

**Category:** Marathon
**Timeout:** 60 minutes
**Tests:** 90 across 12 phases

## Overview

Build an in-memory task queue system through 12 sequential phases. Each phase adds new functionality that builds on prior phases. The phases are designed so that naive implementations of early phases may require refactoring when later phases add constraints.

## What to Build

Implement a `TaskQueue` class in `src/index.ts` (exported as a named export) that supports:

1. **Basic FIFO Queue** - enqueue/dequeue tasks with auto-generated IDs and status tracking
2. **Named Queues** - multiple independent queues identified by name
3. **Priority** - priority levels 1-10 with FIFO within same priority
4. **Delayed/Scheduled Tasks** - delay and runAt options for deferred availability
5. **Retry with Backoff** - automatic retry with exponential backoff on failure
6. **Dead Letter Queue** - tasks that exhaust retries move to DLQ
7. **Task Dependencies** - tasks can depend on other tasks completing first
8. **Concurrency Control** - per-queue limits on concurrent processing
9. **Progress and Cancellation** - progress tracking and task cancellation
10. **Recurring Tasks (Cron)** - scheduled recurring task creation
11. **Middleware Pipeline** - composable middleware for task processing
12. **Graceful Shutdown** - orderly shutdown with timeout and force-cancel

## Phase Details

See the `phases/` directory for detailed descriptions of each phase.

## Validation

```bash
npm test        # All 90 tests must pass
npm run build   # TypeScript must compile
npm run lint    # No lint errors
```

## Constraints

- All implementation goes in `src/index.ts`
- No external runtime dependencies (dev dependencies are provided)
- Must export `TaskQueue` as a named export
- Tests use `vi.useFakeTimers()` for timing-sensitive tests
