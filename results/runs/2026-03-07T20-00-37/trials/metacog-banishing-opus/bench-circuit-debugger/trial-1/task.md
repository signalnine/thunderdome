# Circuit Debugger

Build a circuit simulator and wire-swap debugger for logic gate circuits.

## Data Model

### Gate

```typescript
interface Gate {
  op: 'AND' | 'OR' | 'XOR';
  in1: string;   // input wire name
  in2: string;   // input wire name
  out: string;   // output wire name
}
```

Wires are named with arbitrary strings. Some wires follow naming conventions:
- `x00`, `x01`, ..., `x44` — input bits (X register, bit 0 is least significant)
- `y00`, `y01`, ..., `y44` — input bits (Y register, bit 0 is least significant)
- `z00`, `z01`, ..., `z45` — output bits (Z register, bit 0 is least significant)
- All other wires have random names (e.g., `abc`, `qrs`, `ntg`)

## API

Export two functions from `src/index.ts`:

### `simulate(gates: Gate[], inputs: Record<string, number>): Record<string, number>`

Given a set of gates and initial wire values (0 or 1), simulate the circuit and return the final value of every wire.

Each gate takes two input wires, applies the operation, and writes to the output wire:
- **AND**: output is 1 only if both inputs are 1
- **OR**: output is 1 if at least one input is 1
- **XOR**: output is 1 if exactly one input is 1

Gates can depend on other gates' outputs. Process them in dependency order — a gate can only fire when both its inputs have values. All circuits provided are acyclic (no circular dependencies).

### `findSwappedWires(gates: Gate[]): string[]`

The gates describe a binary adder circuit that computes `X + Y = Z` where X, Y, and Z are multi-bit binary numbers. The circuit has inputs `x00..xNN` and `y00..yNN`, and outputs `z00..z(N+1)` (one extra bit for carry).

However, **exactly 4 pairs of gate output wires have been swapped**. This means 8 gates have incorrect output wire names — each pair had their `out` fields exchanged.

Find all 8 wires involved in swaps and return them as a sorted array of strings.

**Constraint**: Must handle circuits with up to 45 input bits (~220 gates) and return results in under 5 seconds. Brute-force enumeration of swap combinations is not feasible.

## Example: 4-Bit Adder

Here is a correct (un-swapped) 4-bit binary adder. Study its structure — all the circuits you'll debug follow this same pattern but with wires swapped:

```
x00 XOR y00 -> z00     (bit 0: half adder — just XOR, no prior carry)
x00 AND y00 -> c00     (bit 0: carry out)

x01 XOR y01 -> t01     (bit 1: partial sum)
t01 XOR c00 -> z01     (bit 1: final sum = partial XOR carry-in)
x01 AND y01 -> a01     (bit 1: generate carry)
t01 AND c00 -> b01     (bit 1: propagate carry)
a01 OR  b01 -> c01     (bit 1: carry out = generate OR propagate)

x02 XOR y02 -> t02     (bit 2: partial sum)
t02 XOR c01 -> z02     (bit 2: final sum)
x02 AND y02 -> a02     (bit 2: generate carry)
t02 AND c01 -> b02     (bit 2: propagate carry)
a02 OR  b02 -> c02     (bit 2: carry out)

x03 XOR y03 -> t03     (bit 3: partial sum)
t03 XOR c02 -> z03     (bit 3: final sum)
x03 AND y03 -> a03     (bit 3: generate carry)
t03 AND c02 -> b03     (bit 3: propagate carry)
a03 OR  b03 -> c03     (bit 3: carry out)

c03 -> z04              (bit 4: final carry becomes MSB of output)
```

In a swapped circuit, some gate outputs would be exchanged. For example, if `z01` and `a01` were swapped, the gate that should output `z01` would instead output `a01` and vice versa. The two affected gates would have their `out` fields exchanged. Your job is to find all such swapped output wires.

## Commands

```bash
npm test        # run tests
npm run build   # compile TypeScript
npm run lint    # lint source
```

## File Structure

Place your implementation in `src/`. The main entry point should be `src/index.ts`.
