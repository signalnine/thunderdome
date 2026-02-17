# T10: E-Commerce Backend

**Category:** greenfield/complex
**Timeout:** 45 minutes
**Tests:** 48 unit (6 per service) + 22 integration = 70 total

## Overview

Build an event-driven e-commerce backend with 8 independent services communicating through a read-only event bus. Each service implements a specific interface defined in `src/types.ts` and communicates with other services exclusively through events on the shared `EventBus` from `src/bus.ts`.

## What to Build

Implement 8 services, each in its own directory under `src/`:

### src/catalog/index.ts - Product Catalog
- CRUD operations for products (create, get, list, search, update, remove)
- Emits `product:created` events
- Export: `createCatalogService(bus: EventBus): CatalogService`

### src/inventory/index.ts - Inventory Management
- Stock tracking with set, get, reserve, release operations
- Low stock alert system with configurable thresholds
- Emits `inventory:updated` and `inventory:low_stock` events
- Export: `createInventoryService(bus: EventBus): InventoryService`

### src/cart/index.ts - Shopping Cart
- Cart creation, item add/remove/update, clear operations
- Emits `cart:updated` events on any cart modification
- Export: `createCartService(bus: EventBus): CartService`

### src/pricing/index.ts - Price Calculation
- Calculate totals with 10% tax rate
- Discount code support (percentage-based)
- Listens for `product:created` to track prices
- Export: `createPricingService(bus: EventBus): PricingService`

### src/orders/index.ts - Order Management
- Order creation with PENDING initial status
- Status state machine: PENDING -> CONFIRMED -> SHIPPED -> DELIVERED (or CANCELLED)
- Emits `order:created` and `order:status_changed` events
- Export: `createOrderService(bus: EventBus): OrderService`

### src/payment/index.ts - Payment Processing
- Async payment processing with configurable success/failure/timeout simulation
- Refund support for successful transactions
- Emits `payment:processed` events
- Export: `createPaymentService(bus: EventBus, options?: PaymentServiceOptions): PaymentService`

### src/notifications/index.ts - Notification System
- User subscription model
- Listens for `order:status_changed` and `payment:processed` events
- Collects notifications per subscribed user
- Emits `notification:sent` events
- Export: `createNotificationService(bus: EventBus): NotificationService`

### src/analytics/index.ts - Analytics Tracking
- Event counting by type
- Revenue tracking from successful payments
- Conversion rate calculation (orders / unique carts)
- Top products ranking by order quantity
- Listens for all major event types
- Export: `createAnalyticsService(bus: EventBus): AnalyticsService`

## Constraints

- **DO NOT modify** `src/bus.ts` or `src/types.ts` (checksums are validated)
- Each service must take `(bus: EventBus)` as its constructor parameter (payment also accepts options)
- Services must NOT import from each other's directories
- Services communicate ONLY through the event bus
- Each service function is a factory that returns the service interface

## Validation

```bash
npm test        # All 70 tests must pass
npm run build   # TypeScript must compile
npm run lint    # No lint errors
```

## Event Flow

```
catalog --[product:created]--> pricing (tracks prices)
inventory --[inventory:updated]--> (bus log)
inventory --[inventory:low_stock]--> (bus log)
cart --[cart:updated]--> (bus log)
orders --[order:created]--> notifications (maps userId), analytics (tracks)
orders --[order:status_changed]--> notifications (sends notif)
payment --[payment:processed]--> notifications (sends notif), analytics (tracks revenue)
analytics --[analytics:event]--> (bus log)
notifications --[notification:sent]--> (bus log)
```
