# Beam Splitter

Build a beam propagation simulator for a 2D grid laboratory.

## Grid Format

The grid is a 2D array of single-character strings:

- `'S'` — beam source (always on the top row). Emits a beam straight down.
- `'^'` — splitter. When a beam arrives, it splits into two diagonal beams.
- `'.'` — empty cell. Beams pass through.

Beams that leave the grid boundaries are absorbed (they stop).

## Beam Movement Rules

1. A beam from the source `'S'` moves **straight down** (row+1, same column) each step.
2. When a beam hits a splitter `'^'`, it splits into **two beams**:
   - One goes **down-left** (row+1, col-1)
   - One goes **down-right** (row+1, col+1)
   The original beam is consumed by the splitter (it does not continue straight).
3. An unsplit beam (not at a splitter) continues in its current direction:
   - A downward beam continues downward (row+1, same col)
   - A down-left beam continues down-left (row+1, col-1)
   - A down-right beam continues down-right (row+1, col+1)
4. A beam is **absorbed** when it moves outside the grid boundaries (row < 0, row >= rows, col < 0, col >= cols).
5. Multiple beams can occupy the same cell simultaneously.
6. Splitters always split regardless of the beam's incoming direction.

## API

Export two functions from `src/index.ts`:

### `countBeamCells(grid: string[][]): number`

Count the number of distinct cells visited by any beam. A cell counts once even if multiple beams pass through it. The source cell `'S'` counts as visited. Splitter cells hit by beams count as visited.

### `countBeamPaths(grid: string[][]): bigint`

Count the total number of distinct source-to-exit paths through the grid. Each time a beam splits at `'^'`, both branches are separate paths. A path ends when the beam exits the grid (moves beyond any edge).

With K splitters along a beam's path, there are potentially 2^K paths. The result can be astronomically large, so return a `bigint`.

**Performance constraint**: Must handle a 200x200 grid with up to 50 splitters and return results in under 5 seconds. Enumerating individual paths is not feasible for large inputs.

## Example

```
Grid (4 rows x 5 cols):
. S . . .
. . . . .
. ^ . . .
. . . . .
```

- The beam starts at (0,1) where `'S'` is.
- It moves down: (1,1), (2,1) — hits splitter.
- Splits into down-left (3,0) and down-right (3,2).
- Both beams exit the grid after row 3.
- Visited cells: (0,1), (1,1), (2,1), (3,0), (3,2) → `countBeamCells` returns **5**.
- Paths: 2 distinct paths (one ending at (3,0), one at (3,2)) → `countBeamPaths` returns **2n**.

```
Grid with two splitters:
. S . . .
. ^ . . .
^ . ^ . .
. . . . .
```

- Beam starts at (0,1), moves to (1,1) — hits splitter.
- Splits: down-left to (2,0) hits another splitter, down-right to (2,2) hits another splitter.
- (2,0) splitter: sends beams to (3,-1) absorbed and (3,1).
- (2,2) splitter: sends beams to (3,1) and (3,3).
- `countBeamCells`: (0,1), (1,1), (2,0), (2,2), (3,1), (3,3) → **6** (note: two beams land on (3,1) but it counts once).
- `countBeamPaths`: 4 paths total, but one is absorbed → **3n** paths that exit through the bottom or sides at valid cells... Actually, all 4 paths exit (absorbed = exits grid): paths to (3,-1), (3,1), (3,1), (3,3) → **4n**.

## Commands

```bash
npm test        # run tests
npm run build   # compile TypeScript
npm run lint    # lint source
```

## File Structure

Place your implementation in `src/`. The main entry point should be `src/index.ts`.
