# T11: Debug Nightmare

**Category:** bugfix/hard
**Timeout:** 30 minutes

## Description

An event-driven order processing system has several failing tests. The system handles the full order lifecycle: creation, stock reservation, payment, cancellation, and refunds.

Your job: make all tests pass. Do not delete or skip tests. Do not modify test files.

Run `npm test` to see the current failures. There are 30 visible tests — some are currently failing. There is also a hidden test suite that will be run during evaluation.

### Architecture

```
src/
├── events/          # Event bus (publish/subscribe)
├── orders/          # Order lifecycle service + repository
├── inventory/       # Stock management
├── billing/         # Payment processing + price calculation
└── notifications/   # Email/webhook notifications
```

**Flow:** `createOrder()` emits `order.created` → inventory reserves stock → billing charges payment → notification sent. Cancellation and refund flows reverse the process.

### Constraints

- Do not modify any test files.
- `npm run build` and `npm run lint` must pass.
- The system should correctly handle the full order lifecycle.

## Getting Started

```bash
npm install
npm test        # See which tests fail
npm run build   # Verify TypeScript compiles
npm run lint    # Verify lint passes
```
