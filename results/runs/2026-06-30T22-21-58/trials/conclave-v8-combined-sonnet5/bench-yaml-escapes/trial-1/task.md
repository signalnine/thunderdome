# Handle invalid escape sequences in double-quoted scalars

Parsing a double-quoted scalar that contains an invalid `\x` / `\u` / `\U` escape can currently crash instead of reporting a parse error. For example a code point outside the Unicode range (like `"\U00110000"`) throws partway through composition rather than surfacing as a normal document error.

Make these surface as parse errors like other malformed input: `parseDocument` should populate `doc.errors` and keep going, never throw. Valid escapes must keep working unchanged.

(This is a real change harvested from the `yaml` project. Match the codebase's existing conventions for how flow-scalar escape problems are reported.)

## Commands

```bash
npm test          # run the test suite
npm run build     # build
npm run lint      # lint
```
