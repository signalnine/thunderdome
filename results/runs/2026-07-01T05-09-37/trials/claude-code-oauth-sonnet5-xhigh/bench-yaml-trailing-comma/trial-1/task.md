# Add a `trailingComma` stringify option

Add a `trailingComma` boolean option to the document ToString / stringify options (default `false`). When enabled, the last entry in a flow map (`{ ... }`) or flow sequence (`[ ... ]`) should be followed by a trailing comma — but only when that collection is rendered across multiple lines. A flow collection that fits on a single line must not gain a trailing comma.

(This is a real feature harvested from the `yaml` project. Match the codebase's existing conventions for stringify options and flow-collection formatting, and make it interact correctly with the existing line-width wrapping.)

## Commands

```bash
npm test          # run the test suite
npm run build     # build
npm run lint      # lint
```
