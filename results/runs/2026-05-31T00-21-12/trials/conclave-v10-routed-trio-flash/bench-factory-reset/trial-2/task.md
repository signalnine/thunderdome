# Factory Reset

Solve button-toggle puzzles for a factory machine control panel.

## Part 1: Toggle Puzzle

A machine has N lights, all initially **off** (false). There are M buttons. Each button, when pressed, **toggles** a specific set of lights (off→on, on→off). Each button can be pressed **at most once** (0 or 1 presses).

Find the minimum set of buttons to press so that the lights match a target configuration.

### Data Model

```typescript
interface Machine {
  target: boolean[];     // desired state for each light (all start off)
  buttons: number[][];   // buttons[i] = array of light indices toggled by button i
}
```

### API

```typescript
function solveToggle(machine: Machine): number[] | null;
```

- Return an array of **button indices** (0-based) to press, sorted in ascending order.
- If multiple solutions exist, return the one with the **fewest button presses**.
- If tied on press count, return the **lexicographically smallest** set of indices.
- Return `null` if no solution exists.

### Example

```
Lights: 4 (indices 0-3), all start off
Target: [true, true, false, true]
Buttons:
  0: toggles lights [0, 1]
  1: toggles lights [1, 2, 3]
  2: toggles lights [0, 3]

Press buttons 0 and 1:
  Button 0: lights become [on, on, off, off]
  Button 1: lights become [on, off, on, on]
  Wait — that gives [true, false, true, true], not the target.

Press buttons 1 and 2:
  Button 1: [off, on, on, on]
  Button 2: [on, on, on, off]
  That gives [true, true, true, false], also wrong.

Press buttons 0, 1, 2:
  After 0: [on, on, off, off]
  After 1: [on, off, on, on]
  After 2: [off, off, on, off]
  Wrong again.

Correct: press buttons 0 and 2:
  After 0: [on, on, off, off]
  After 2: [off, on, off, on]
  Result: [false, true, false, true]
  Hmm, that's not the target either.

Actually, let's re-check: target is [true, true, false, true].
  Press button 2: toggles [0, 3] → [on, off, off, on]
  Press button 1: toggles [1, 2, 3] → [on, on, on, off]
  Not matching.

  Press button 0: toggles [0, 1] → [on, on, off, off]
  Press button 1: toggles [1, 2, 3] → [on, off, on, on]
  Press button 2: toggles [0, 3] → [off, off, on, off]
  Still wrong.

The toggle order doesn't matter (toggling is commutative). So for target [T, T, F, T]:
We need light 0=on, 1=on, 2=off, 3=on.
Button 0 affects {0,1}, Button 1 affects {1,2,3}, Button 2 affects {0,3}.
We need: b0 XOR b2 = 1 (light 0), b0 XOR b1 = 1 (light 1), b1 = 0 (light 2), b1 XOR b2 = 1 (light 3).
From light 2: b1=0. From light 1: b0=1. From light 0: b2=0. Check light 3: 0 XOR 0 = 0 ≠ 1. No solution!

solveToggle returns null.
```

**Constraint**: Must handle up to 40 buttons and 40 lights and return results in under 5 seconds. Brute-force enumeration of all 2^40 button combinations is not feasible.

## Part 2: Counter Puzzle

A variant where lights are replaced by **counters**. Each counter starts at 0. Buttons **increment** (not toggle) specific counters by 1. Counters wrap around at a given modulus (e.g., mod 5 means values cycle 0→1→2→3→4→0).

Each button can be pressed **multiple times** (0 to modulus-1 times).

```typescript
function solveCounter(
  lights: number[],      // target counter values (each 0..modulus-1)
  buttons: number[][],   // buttons[i] = indices of counters affected
  modulus: number        // counters wrap at this value (always prime)
): number[] | null;
```

- Return an array where `result[i]` is the number of times button `i` should be pressed (0 to modulus-1).
- If multiple solutions exist, return the one with the **minimum total presses** (sum of all result values).
- If tied on total, return the **lexicographically smallest** result array.
- Return `null` if no solution exists.
- The modulus is always a **prime number**.

**Constraint**: Must handle up to 40 buttons, 40 counters, and modulus up to 97. Must complete in under 5 seconds.

## Commands

```bash
npm test        # run tests
npm run build   # compile TypeScript
npm run lint    # lint source
```

## File Structure

Place your implementation in `src/`. The main entry point should be `src/index.ts`.
