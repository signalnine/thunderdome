# Multi-Agent Consensus Framework

Reusable infrastructure for multi-agent consensus. Any skill can invoke Claude, Gemini, and Codex to get diverse perspectives on prompts, designs, code, or decisions.

## Purpose

Different AI models have different strengths and weaknesses. Single agents may miss issues, exhibit biases, or have blind spots. This framework provides consensus from multiple agents, grouped by agreement level.

## Architecture

**Design:** `docs/plans/2025-12-13-multi-agent-consensus-framework-design.md`

**Key components:**
- Mode-based interface (code-review vs general-prompt)
- Two-stage synthesis process (parallel analysis + chairman consensus)
- Three-tier output (High/Medium/Consider priority)
- Graceful degradation (works with 1, 2, or 3 reviewers)

## Setup

### Required Dependencies

**1. curl & jq**

Required for API calls:

```bash
# Check if installed
curl --version
jq --version

# Install if needed (macOS):
brew install curl jq

# Install if needed (Debian/Ubuntu):
sudo apt-get install curl jq
```

**2. Bash 4.0+ & bc**
```bash
# Check versions
bash --version
bc --version

# macOS: upgrade if needed
brew install bash bc

# Debian/Ubuntu:
sudo apt-get install bash bc
```

**3. git**
```bash
# Check if installed
git --version
```

### Agent API Keys

At least one agent is required. More agents provide better consensus.

**Claude Agent (Recommended Primary)**

```bash
# Get API key from: https://console.anthropic.com/

# Set environment variable
export ANTHROPIC_API_KEY="sk-ant-..."

# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc

# Optional: Configure model and token limit
export ANTHROPIC_MODEL="claude-opus-4-5-20251101"
export ANTHROPIC_MAX_TOKENS="16000"  # Default: 16000, adjust if using models with lower limits
```

**Gemini Agent (Optional but Recommended)**

```bash
# Get API key from: https://ai.google.dev/

# Set environment variable
export GEMINI_API_KEY="..."

# Add to your shell profile
echo 'export GEMINI_API_KEY="..."' >> ~/.bashrc

# Optional: Configure model (default: gemini-3-pro-preview)
export GEMINI_MODEL="gemini-3-pro-preview"
```

**OpenAI Agent (Optional)**

Provides the OpenAI/GPT perspective:

```bash
# Get API key from: https://platform.openai.com/

# Set environment variable
export OPENAI_API_KEY="sk-..."

# Add to your shell profile
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.bashrc

# Optional: Configure model and token limit
export OPENAI_MODEL="gpt-5.1-codex-max"
export OPENAI_MAX_TOKENS="16000"  # Default: 16000, adjust if using models with lower limits (e.g., 4096 for gpt-4-turbo)
```

### Minimum Requirements

**For basic functionality:**
- At least one API key (ANTHROPIC_API_KEY, GEMINI_API_KEY, or OPENAI_API_KEY)
- curl, jq, bash, bc, git

**For full consensus (recommended):**
- All three API keys: ANTHROPIC_API_KEY, GEMINI_API_KEY, and OPENAI_API_KEY
- This provides three independent perspectives from Claude, Gemini, and OpenAI

## Verification

Test your setup:

```bash
# Test basic functionality (uses Claude only)
./skills/multi-agent-consensus/test-consensus-synthesis.sh

# Test with actual reviewers
echo "test" > /tmp/test.txt
git init /tmp/test-repo
cd /tmp/test-repo
git add test.txt
git commit -m "initial"
BASE=$(git rev-parse HEAD)
echo "modified" > test.txt
git add test.txt
git commit -m "change"
HEAD=$(git rev-parse HEAD)

# This will show which reviewers are available
../path/to/skills/multi-agent-consensus/consensus-synthesis.sh --mode=code-review \
  --base-sha="$BASE" --head-sha="$HEAD" --description="test"

# Look for:
# Claude: ✓ (always works)
# Gemini: ✓ or ✗ (not installed)
# Codex: ✓ or ✗ (not available)
```

## Usage

### Code Review Mode

```bash
skills/multi-agent-consensus/consensus-synthesis.sh --mode=code-review \
  --base-sha="abc123" \
  --head-sha="def456" \
  --plan-file="docs/plans/feature.md" \
  --description="Add authentication"
```

### General Prompt Mode

```bash
skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="What could go wrong with this design?" \
  --context="$(cat design.md)"
```

## Output Format

Three-tier consensus report:

```markdown
## High Priority - All Reviewers Agree
- [SEVERITY] description
  - Claude: "issue text"
  - Gemini: "issue text"
  - Codex: "issue text"

## Medium Priority - Majority Flagged (2/3)
- [SEVERITY] description
  - Claude: "issue text"
  - Gemini: "issue text"

## Consider - Single Reviewer Mentioned
- [SEVERITY] description
  - Codex: "issue text"
```

## How It Works

**Stage 1: Parallel Independent Analysis**
- Claude, Gemini, and Codex analyze the prompt independently
- Each provides structured feedback (Critical/Important/Suggestions)
- 60-second timeout per agent (configurable)
- Results collected from all successful agents

**Stage 2: Chairman Synthesis**
- Chairman agent (Claude → Gemini → Codex fallback) synthesizes consensus
- Groups issues by agreement level
- Highlights disagreements explicitly
- Produces final three-tier report
- 60-second timeout (configurable)

## Dependencies

- Bash 4.0+
- git
- bc (for calculations)
- curl (for API calls)
- jq (for JSON parsing)
- ANTHROPIC_API_KEY (for Claude agent)
- GEMINI_API_KEY (for Gemini agent)
- OPENAI_API_KEY (for OpenAI agent)

## Configuration

### Timeout Settings

Default timeouts are 60 seconds per stage, covering P95-P99 API latency scenarios.

**Via environment variables:**
```bash
export CONSENSUS_STAGE1_TIMEOUT=90  # Stage 1 timeout in seconds
export CONSENSUS_STAGE2_TIMEOUT=90  # Stage 2 timeout in seconds
```

**Via CLI flags:**
```bash
consensus-synthesis.sh --mode=general-prompt \
  --prompt="Your question" \
  --stage1-timeout=90 \
  --stage2-timeout=90
```

**When to adjust:**
- **Increase (90-120s):** Very large code diffs, complex architectural questions, slow networks
- **Decrease (30-45s):** Simple prompts, fast iteration, when speed is critical
- **Default (60s):** Recommended for most use cases

## Integration Examples

### Already Integrated

**1. Brainstorming (design validation)**

After design approval, offers multi-agent validation:
```bash
DESIGN=$(cat docs/plans/2025-12-13-feature-design.md)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Review this design for architectural flaws, over-engineering, missing requirements, maintainability concerns, or testing gaps. Rate as STRONG/MODERATE/WEAK." \
  --context="$DESIGN"
```

**2. Requesting Code Review**

Automatically uses consensus framework:
```bash
skills/multi-agent-consensus/consensus-synthesis.sh --mode=code-review \
  --base-sha="abc123" --head-sha="def456" \
  --description="Add authentication feature"
```

### Ready to Integrate

**3. Architecture Decisions**

Get consensus on technical choices:
```bash
skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Which approach is better for this use case and why? Rate confidence as STRONG/MODERATE/WEAK." \
  --context="Option A: Redis caching. Option B: In-memory caching. Use case: 1000 req/sec API with 5-minute session TTL."
```

**4. Debugging (root cause analysis)**

Multiple perspectives on error causes:
```bash
ERROR_CONTEXT="Stack trace shows null pointer in database connection pool. Happens randomly under load."

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="What could cause this error? List potential root causes. Rate likelihood as STRONG/MODERATE/WEAK." \
  --context="$ERROR_CONTEXT"
```

**5. Security Review**

Consensus on security concerns:
```bash
CODE=$(cat src/auth/login.py)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Identify security vulnerabilities in this authentication code. Rate severity as STRONG/MODERATE/WEAK." \
  --context="$CODE"
```

**6. Performance Optimization**

Get diverse perspectives on bottlenecks:
```bash
PROFILE_DATA=$(cat profiling-results.txt)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Analyze this performance profile. What are the bottlenecks and how should they be addressed? Rate impact as STRONG/MODERATE/WEAK." \
  --context="$PROFILE_DATA"
```

**7. API Design Review**

Consensus on interface design:
```bash
API_SPEC=$(cat openapi.yaml)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Review this API design for usability issues, inconsistencies, or missing endpoints. Rate importance as STRONG/MODERATE/WEAK." \
  --context="$API_SPEC"
```

**8. Refactoring Decisions**

Should you refactor and how:
```bash
LEGACY_CODE=$(cat legacy-module.js)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Should this code be refactored? If yes, what approach? Rate urgency as STRONG/MODERATE/WEAK." \
  --context="$LEGACY_CODE"
```

**9. Debugging (systematic-debugging)**

Validate root cause hypothesis before implementing fix:

```bash
# Example debugging context
CONTEXT=$(cat << 'EOF'
## Error Description
Test fails: "Expected 5, got 3"
All calculation tests fail with off-by-two errors
Started after recent refactor of calculation logic

## Evidence Collected
- Reproduction: 100% failure rate on TestCase.test_calculation
- Stack trace points to calculation() in math.py:42
- Git diff shows loop initialization changed from 0 to 1
- Manual trace confirms loop runs one fewer iteration than expected

## Root Cause Hypothesis
Off-by-two error introduced in refactor - loop starts at 1 instead of 0.
This causes calculation to skip first two elements (index 0 and 1).

## Proposed Fix
Change loop initialization from `for i in range(1, len(arr))` to `for i in range(len(arr))`
EOF
)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Review this root cause analysis. Does the hypothesis explain all observed symptoms? Are there alternative explanations we should consider? Are there gaps in the evidence? Rate your confidence in this diagnosis as STRONG/MODERATE/WEAK." \
  --context="$CONTEXT"
```

**10. Debugging (root-cause-tracing)**

Validate traced causal path from symptom to root trigger:

```bash
# Example tracing context
CONTEXT=$(cat << 'EOF'
## Error Description
Git init fails with "directory not found: /Users/jesse/project/packages/core"
Error occurs deep in execution (WorktreeManager.createWorktree)

## Evidence Collected
Traced backward through call stack:
1. Error at: git init in WorktreeManager.createWorktree() line 67
2. Called by: Session.initializeWorkspace() line 123
3. Called by: Session.create() line 45
4. Called by: test Project.create() line 12
5. Root trigger: Test doesn't initialize projectDir before calling Project.create()
   - projectDir passed as empty string ''
   - Empty string propagates through all calls
   - Reaches git init as invalid path

## Root Cause Hypothesis
Test setup missing: projectDir = '/tmp/test-project' assignment before Project.create()
Test assumes projectDir is initialized but it's not.

## Proposed Fix
Add to test setup:
```
projectDir = '/tmp/test-project'
fs.mkdirSync(projectDir)
```
EOF
)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Review this causal trace from symptom to root trigger. Is the traced path complete and correct? Are there missing causal links? Could the symptom have a different root trigger? Rate your confidence in this trace as STRONG/MODERATE/WEAK." \
  --context="$CONTEXT"
```

## Testing

```bash
./skills/multi-agent-consensus/test-consensus-synthesis.sh
```

## Migration from multi-review.sh

Old code review calls:
```bash
skills/requesting-code-review/multi-review.sh "$BASE" "$HEAD" "$PLAN" "$DESC"
```

New code review calls:
```bash
skills/multi-agent-consensus/consensus-synthesis.sh --mode=code-review \
  --base-sha="$BASE" --head-sha="$HEAD" \
  --plan-file="$PLAN" --description="$DESC"
```
