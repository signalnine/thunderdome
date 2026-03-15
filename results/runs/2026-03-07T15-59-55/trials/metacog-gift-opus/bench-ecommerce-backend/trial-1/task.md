# E-Commerce Backend

Build an event-driven e-commerce backend composed of 8 independent services that communicate through a shared event bus.

## Provided Files (read-only)

- **`src/bus.ts`** -- An `EventBus` class with `on`, `off`, `emit`, `getLog`, and `clear` methods. Do not modify this file.
- **`src/types.ts`** -- TypeScript interfaces for all 8 services, event payload types, enums (`OrderStatus`, `PaymentStatus`), and event name constants. Do not modify this file.

## Architecture

Each service is a factory function that receives an `EventBus` instance and returns an object conforming to the corresponding interface from `types.ts`. Services must not import from one another -- all inter-service communication happens through events on the bus.

## Services to Implement

1. **Catalog** -- Manage a product catalog. Support creating, retrieving, listing, searching, updating, and removing products. Emit events when products are created.

2. **Inventory** -- Track stock levels for products. Support setting stock, checking quantities, reserving stock for orders, and releasing reserved stock. Detect low-stock conditions and alert when stock falls below configurable thresholds.

3. **Cart** -- Manage shopping carts for users. Support creating carts, adding/removing items, updating quantities, clearing carts, and retrieving cart contents. Items for the same product added multiple times should consolidate.

4. **Pricing** -- Calculate order totals including tax (10% rate). Support registering percentage-based discount codes that reduce the subtotal before tax is applied. Listen for product creation events to track product prices.

5. **Orders** -- Create and manage orders. Orders start in a pending state and progress through a status lifecycle (confirmed, shipped, delivered) with the option to cancel. Emit events on creation and status changes, including the previous status.

6. **Payment** -- Process payments asynchronously. Support configurable simulation of success, failure, and timeout scenarios via an options parameter. Support refunding successful transactions. Emit events when payments are processed.

7. **Notifications** -- Deliver notifications to subscribed users. Listen for order status changes and payment events, then record notifications for the relevant user. Track which orders belong to which users.

8. **Analytics** -- Track platform-wide metrics by listening to events on the bus. Count events by type, track revenue from successful payments, calculate conversion rates (orders divided by unique carts), and rank products by order quantity.

## Project Structure

Each service should live in its own subdirectory under `src/` (directories already exist):

```
src/catalog/index.ts
src/inventory/index.ts
src/cart/index.ts
src/pricing/index.ts
src/orders/index.ts
src/payment/index.ts
src/notifications/index.ts
src/analytics/index.ts
```

Export all 8 service factory functions from `src/index.ts`.

## Factory Function Names

Each factory follows the pattern `create<Name>Service(bus: EventBus)`. The payment service additionally accepts an optional options parameter for simulation configuration.

## Validation

```bash
npm run build   # TypeScript must compile cleanly
npm run lint    # No lint errors
```

Writing your own tests is strongly encouraged to verify correctness before submission.
