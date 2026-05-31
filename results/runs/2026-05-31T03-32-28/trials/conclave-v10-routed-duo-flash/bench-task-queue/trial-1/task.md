# Task Queue System

Build a fully-featured in-memory task queue system from scratch. The system should grow incrementally through 12 phases, each introducing new capabilities that build on the foundation laid by earlier phases.

## Overview

Your task queue should support adding tasks, processing them, and managing their lifecycle. Think of it like a simplified version of systems like Bull, BeeQueue, or Celery -- but entirely in-memory with no external dependencies.

The system evolves through 12 phases of increasing sophistication:

1. **Basic queue** -- adding and processing tasks in order
2. **Named queues** -- multiple independent queues
3. **Priority** -- some tasks are more urgent than others
4. **Delayed tasks** -- tasks that should wait before becoming available
5. **Retry with backoff** -- automatic retry when tasks fail
6. **Dead letter queue** -- permanent storage for repeatedly-failing tasks
7. **Task dependencies** -- tasks that wait for other tasks to finish
8. **Concurrency control** -- limiting how many tasks run at once
9. **Progress and cancellation** -- tracking and aborting work
10. **Recurring tasks** -- cron-like scheduled task creation
11. **Middleware** -- intercepting and transforming tasks in a pipeline
12. **Graceful shutdown** -- orderly wind-down of the system

Read `phases/*.md` for detailed requirements for each phase.

## Getting Started

- Export your main API from `src/index.ts`
- All implementation should live under `src/`
- No external runtime dependencies allowed (dev dependencies are pre-installed)
- Write your own tests as you go to verify your implementation

## Validation

```bash
npm run build   # TypeScript must compile
npm run lint    # No lint errors
```

## Tips

- Later phases will force you to rethink early decisions. Design with extensibility in mind.
- Tasks should have unique identifiers and track their lifecycle status.
- Consider how features like priorities, delays, and dependencies interact with each other.
