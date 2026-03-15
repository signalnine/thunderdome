# T14: Financial Ledger

**Category:** bugfix/hard
**Timeout:** 30 minutes

## Description

You're maintaining a double-entry accounting ledger library. The library tracks accounts, journal entries (transactions), and provides reporting functions (trial balance, account statements, P&L).

Several bugs have been reported. The test suite has 40 tests, but only 31 are currently passing (8 bugs cause 9 test failures). Your job is to fix all the bugs so that all 40 tests pass.

## Architecture

The library is in `src/ledger.ts` and exports:

- `Ledger` class with methods:
  - `createAccount(name, type, currency?)` — Create a named account (asset, liability, equity, revenue, expense). Optional currency defaults to "USD".
  - `postEntry(description, debits, credits, date?)` — Post a journal entry with debit/credit line items. Each line is `{ account: string, amount: number }`. Debits must equal credits. Optional date defaults to now.
  - `getBalance(accountName)` — Get current balance for an account. Assets/expenses have normal debit balances; liabilities/equity/revenue have normal credit balances.
  - `getTrialBalance()` — Returns all account balances. Total debits must equal total credits.
  - `getStatement(accountName, startDate?, endDate?)` — Returns chronological list of entries affecting an account, with running balance.
  - `splitEntry(description, fromAccount, toAccounts, totalAmount, date?)` — Convenience method: split a total amount across multiple destination accounts. `toAccounts` is `{ account: string, amount: number }[]`. Creates a journal entry debiting `fromAccount` and crediting each destination.
  - `getAccountsByType(type)` — Returns all accounts of a given type.
  - `getProfitAndLoss(startDate?, endDate?)` — Returns revenue minus expenses for the period.

## Known Issues

Users have reported:
1. Trial balance doesn't balance in some scenarios
2. Account statements show wrong running balances
3. Split entries sometimes create unbalanced journal entries
4. Date filtering in statements is off-by-one
5. P&L calculation has sign errors
6. Currency mismatch validation isn't working
7. Duplicate account names aren't rejected
8. getBalance returns wrong sign for liability accounts

## Validation

```bash
npm test      # Run tests (32/40 passing currently)
npm run build # Should compile cleanly
npm run lint  # Should pass
```
