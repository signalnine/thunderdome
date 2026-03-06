# Reactive Spreadsheet Engine

Build a spreadsheet engine as a TypeScript library. The engine manages a grid of cells that can contain values or formulas, with automatic reactive updates when dependencies change.

## Cell References

Cells are referenced by column letter(s) followed by a row number: `A1`, `B2`, `Z100`, `AA1`, etc. Columns use letters A-Z, then AA-AZ, BA-BZ, etc. Rows are 1-based integers.

## Cell Values

A cell can contain:
- **Numbers**: `42`, `3.14`
- **Strings**: `"hello"` (text values)
- **Booleans**: `true`, `false`
- **Formulas**: expressions starting with `=` (e.g., `=A1+B1`, `=SUM(A1:A5)`)

## Formulas

Formulas begin with `=` and support:
- **Arithmetic operators**: `+`, `-`, `*`, `/`
- **Parentheses** for grouping: `=(A1+B1)*2`
- **Cell references**: `=A1`, `=B2+C3`
- **Comparison operators**: `>`, `<`, `>=`, `<=`, `=`, `<>` (used in IF conditions)

## Built-in Functions

- `SUM(range)` — sum of all numeric values in the range
- `AVERAGE(range)` — arithmetic mean of numeric values in the range
- `MIN(range)` — smallest numeric value in the range
- `MAX(range)` — largest numeric value in the range
- `COUNT(range)` — count of numeric values in the range
- `IF(condition, trueValue, falseValue)` — conditional expression

## Ranges

Ranges are specified as `start:end`:
- **Column range**: `A1:A5` — cells A1, A2, A3, A4, A5
- **Row range**: `A1:C1` — cells A1, B1, C1
- **Block range**: `A1:C3` — all cells in the 2D rectangle from A1 to C3

## Reactive Updates

When a cell's value changes, all cells that depend on it (directly or transitively) must automatically recompute. For example, if `B1` contains `=A1+1` and `A1` changes from `5` to `10`, then `B1` should automatically update from `6` to `11`.

## Circular Reference Detection

If setting a cell would create a circular dependency (e.g., `A1=B1` and `B1=A1`), the engine must detect this and throw an error. This includes indirect cycles through any number of intermediate cells.

## API

Export a `Spreadsheet` class (or equivalent) from `src/index.ts` with the following interface:

```typescript
class Spreadsheet {
  // Set a cell's value. Can be a raw value or a formula string starting with '='
  set(cell: string, value: string | number | boolean): void;

  // Get a cell's computed value. Returns null for empty cells.
  get(cell: string): string | number | boolean | null;

  // Get the display string for a cell's computed value.
  getDisplay(cell: string): string;

  // Get all non-empty cells as a Map from cell reference to computed value.
  getCells(): Map<string, any>;
}
```

## Example Usage

```typescript
const sheet = new Spreadsheet();

sheet.set('A1', 10);
sheet.set('A2', 20);
sheet.set('A3', '=A1+A2');
sheet.get('A3');        // 30
sheet.getDisplay('A3'); // "30"

sheet.set('A1', 50);
sheet.get('A3');        // 70  (reactively updated)

sheet.set('B1', '=SUM(A1:A2)');
sheet.get('B1');        // 70

sheet.set('C1', '=IF(A1>30, "big", "small")');
sheet.get('C1');        // "big"
```

## Requirements

- Implement in TypeScript with proper types
- Export from `src/index.ts`
- Write tests using Vitest
- All code in the `src/` directory
