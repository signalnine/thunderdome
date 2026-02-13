# Prose Linting for Conclave

## Context

Conclave has 18 SKILL.md files with strict authoring rules (YAML frontmatter schema, "Use when" description prefix, word count targets, naming conventions) and design documents in `docs/plans/` with filename conventions. Currently there is zero automated enforcement of these rules — compliance relies entirely on skill authors following the `writing-skills` guide.

## Design

A pure Go linter (`conclave lint`) that validates SKILL.md files and `docs/plans/` filenames against Conclave's authoring standards. Implemented as `internal/lint` package with a Cobra CLI command.

### CLI Interface

```
conclave lint                                  # scan all skills + docs/plans/ from git root
conclave lint skills/brainstorming/SKILL.md    # lint a single file
conclave lint skills/ docs/plans/              # lint specific directories
conclave lint --json                           # machine-readable output
conclave lint --word-limit 300                 # override word count threshold
```

Exit code 0 means no errors (warnings are OK). Exit code 1 means at least one error.

**Root discovery:** The command finds the repository root by running `git rev-parse --show-toplevel`. If not in a git repo, it uses the current working directory. When no paths are given, it scans `skills/` and `docs/plans/` relative to the root.

**Partial scan with global rules:** When specific paths are provided, the linter still discovers all skills from the repository root for `duplicate-name` and `cross-ref-valid` checks. These rules require global knowledge. Per-file rules (frontmatter, naming, word count) apply only to the specified paths.

Human-readable output:

```
skills/brainstorming/SKILL.md
  error: description must start with "Use when" (got: "Interactive design...")
  warning: word count 523 exceeds 500 word target

docs/plans/bad-name.md
  error: filename must match YYYY-MM-DD-<topic>-{design,implementation}.md

Found 2 errors, 1 warning in 19 files
```

JSON output (`--json`):

```json
[
  {
    "file": "skills/brainstorming/SKILL.md",
    "rule": "description-prefix",
    "severity": "error",
    "message": "description must start with \"Use when\" (got: \"Interactive design...\")"
  }
]
```

### Lint Rules

**Errors** (fail the lint, exit 1):

| Rule | Check |
|------|-------|
| `frontmatter-required` | SKILL.md must have YAML frontmatter with `name` and `description` fields |
| `frontmatter-schema` | No unexpected fields beyond `name` and `description` |
| `description-prefix` | Description must start with "Use when" |
| `description-length` | Description must be <= 1024 characters |
| `skill-naming` | Skill `name` field must match `^[a-z0-9]+(-[a-z0-9]+)*$` (lowercase letters, numbers, hyphens) |
| `cross-ref-valid` | `**REQUIRED BACKGROUND:**` and `**REQUIRED SUB-SKILL:**` markers must reference skills that exist |
| `duplicate-name` | No two skills may share the same `name` value |
| `plan-filename` | Files in `docs/plans/` must match `YYYY-MM-DD-<topic>-{design,implementation}.md` (dotfiles excluded) |

**Warnings** (reported but don't fail):

| Rule | Check |
|------|-------|
| `word-count` | SKILL.md body (excluding frontmatter) exceeds 500 words |
| `description-verbose` | Description exceeds 200 characters |

### Package Architecture

Three files to create, no existing files modified:

| File | Purpose |
|------|---------|
| `internal/lint/lint.go` | Core linting engine — rule definitions, file scanning, result aggregation |
| `internal/lint/lint_test.go` | Unit tests with in-memory SKILL.md fixtures |
| `cmd/conclave/lint.go` | Cobra command wiring, flag parsing, output formatting |

Public API:

```go
type Severity int  // Error or Warning

type Finding struct {
    File     string
    Rule     string
    Severity Severity
    Message  string
}

type Result struct {
    Findings []Finding
    Files    int
}

func LintSkills(paths []string, knownSkills []string) (*Result, error)
func LintPlanFilenames(dir string) (*Result, error)
```

Each rule is a function that takes parsed skill data and returns zero or more `Finding` values. No new dependencies — uses `strings`, `regexp`, `path/filepath`, `os`, and `gopkg.in/yaml.v3` (already in go.mod).

**YAML frontmatter parsing:** The linter parses frontmatter by splitting on `---` delimiters and unmarshalling into a `map[string]interface{}` (not a struct). This allows detecting unexpected fields — any key besides `name` and `description` triggers the `frontmatter-schema` error. This differs from `internal/skills/discovery.go` which unmarshals into a struct and silently ignores unknown fields.

**Cross-reference validation:** The linter calls `internal/skills.FindAllSkills(rootDir)` (or equivalent) to build the set of known skill names, then scans for `**REQUIRED BACKGROUND:**` and `**REQUIRED SUB-SKILL:**` marker patterns and validates each referenced name exists. The linter handles malformed skill files gracefully — a skill with broken frontmatter produces its own findings but doesn't prevent cross-ref validation of other skills.

**Plan filename pattern:** Files in `docs/plans/` must match `^\d{4}-\d{2}-\d{2}-.+-(?:design|implementation)\.md$`. Files starting with `.` are excluded. The `<topic>` segment allows lowercase letters, numbers, and hyphens.

### Workflow Integration

1. **Manual**: `conclave lint` run by skill authors at will
2. **Skill checklist**: Add lint step to `writing-skills` skill instructions
3. **Hook** (opt-in): Available via `conclave hook` infrastructure, must complete in < 2 seconds

### Testing Strategy

Unit tests in `internal/lint/lint_test.go` using `t.TempDir()` fixtures:

- Valid skill produces zero findings
- Missing/malformed frontmatter → error
- Missing required fields → error
- Unexpected frontmatter fields → error
- Description prefix, length, verbosity checks
- Skill naming violations (underscores, spaces, uppercase)
- Word count threshold
- Cross-reference to existing skill → no finding
- Cross-reference to nonexistent skill → error
- Duplicate skill names → error
- Valid and invalid plan filenames
- Dotfiles in docs/plans/ are skipped
- JSON output produces valid JSON

Integration smoke test (build tag `integration`):

- Run `conclave lint` on the actual `skills/` directory, assert exit 0
- Run `conclave lint` on a temp dir with known-bad fixtures, assert exit 1

### Out of Scope

- General markdown linting (heading hierarchy, broken links, formatting) — backlog item, add when evidence justifies
- Consensus output validation — conflates linting with evals, defer indefinitely
- Natural language style checks (passive voice, readability) — not needed for structural validation
- `--fix` flag — future enhancement
