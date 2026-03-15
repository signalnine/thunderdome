# Constraint-Based Event Scheduler

Build a constraint-based event scheduler that assigns events to rooms within a time window, respecting capacity limits, prerequisite ordering, and room preferences.

## Data Model

### Event
```typescript
interface Event {
  id: string;
  name: string;
  duration: number;       // in minutes
  attendees?: number;     // number of people attending (default: 1)
  prerequisites?: string[]; // event IDs that must finish before this starts
  preferredRoom?: string; // room ID preference (hint, not hard constraint)
}
```

### Room
```typescript
interface Room {
  id: string;
  name: string;
  capacity: number;       // max attendees
}
```

### Schedule Options
```typescript
interface ScheduleOptions {
  startTime: number;      // minutes from midnight (e.g., 540 = 9:00 AM)
  endTime: number;        // minutes from midnight (e.g., 1020 = 5:00 PM)
  gap?: number;           // minimum gap in minutes between events in same room (default: 15)
}
```

### Output
```typescript
interface Assignment {
  eventId: string;
  roomId: string;
  startTime: number;      // minutes from midnight
  endTime: number;        // minutes from midnight
}

interface ScheduleResult {
  assignments: Assignment[];
  unscheduled: string[];  // event IDs that could not be scheduled
}
```

## API

Export a `schedule` function (named export, default export, or via a `Scheduler` class / `createScheduler` factory):

```typescript
function schedule(events: Event[], rooms: Room[], options: ScheduleOptions): ScheduleResult;
```

## Scheduling Rules

1. **Room capacity**: An event's `attendees` count must not exceed the room's `capacity`.
2. **Time window**: Every event must start and end within `[options.startTime, options.endTime]`.
3. **Room gaps**: Events in the same room must have at least `options.gap` minutes between them (end of one event to start of the next). Default gap is 15 minutes.
4. **Prerequisites**: If event B lists event A in its `prerequisites`, then A must finish before B can start. The gap between prerequisite events also applies (A's end time + gap <= B's start time).
5. **Preferred room**: When an event specifies a `preferredRoom`, honor it if possible without violating other constraints.
6. **Prerequisite cycles**: If the prerequisite graph contains a cycle (including self-references), throw an error.
7. **Batch optimization**: Schedule all events at once, maximizing the number of events successfully scheduled. Events that cannot be placed should appear in `unscheduled`.

## Behavior

- The scheduler should maximize the number of events scheduled. Simply fitting events in order is not sufficient -- the scheduler should consider how placing one event affects the ability to place others.
- When events cannot be scheduled due to conflicting constraints, they should be listed in `unscheduled` rather than throwing an error.
- Prerequisite cycles (including self-references like `A -> A`) must throw an error, not silently skip.

## Commands

```bash
npm test        # run tests
npm run build   # compile TypeScript
npm run lint    # lint source
```

## File Structure

Place your implementation in `src/`. The main entry point should be `src/index.ts` (or `src/scheduler.ts` re-exported from `src/index.ts`).
