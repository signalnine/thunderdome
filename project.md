Agentic Thunderdome
Two agents enter, one agent leaves
Created: 2026-02-04 Status: Active Priority: Medium
Overview
Benchmarking framework to compare agentic coding orchestrators head-to-head. Pit different tools against standardized tasks and measure what actually matters.
Contenders
* Conclave (Superpowers fork) - Multi-agent consensus for architecture/brainstorming and code reviews, auto-pilot brainstorming mode, Ralph loop runner for fresh context windows in subagent runs
    * Consensus uses cross-provider models: Codex Max × Opus × Gemini 3 Pro
    * Different training = different blind spots = real disagreement, not echo chamber
* Superpowers (Original)
* Amplifier
* Gas Town
* Others TBD
Key Differentiators to Test
Multi-Agent Consensus
* Architecture coherence (do implementations match the plan?)
* Rework rate (how often backtrack after review?)
* Defect escape rate (bugs consensus should have caught)
* Key insight: Biggest value is catching bad designs before implementation - front-loaded quality gate vs post-hoc detection
* Key insight: Also catches code bugs in review phase extremely well - multiple perspectives find issues a single agent misses
Auto-Pilot Brainstorming
* Compare human-in-loop vs auto-pilot on same tasks
* Measure "drift" - does it go off the rails without correction?
* Time-to-first-implementation-attempt
Ralph Loop Runner / Fresh Context
* Success rate on long tasks (where context degradation kills other tools)
* Token usage for equivalent outcomes
* Compare vs single-long-context approaches
* Key insight: Most Ralph loop implementations forget the "fresh context" part entirely - they loop but accumulate stale context anyway
Benchmark Dimensions
Metric  Description
Completion Rate Does it actually solve the problem?
Token Efficiency    Cost per task
Turn Count  Iterations to converge
Error Recovery  Can it dig out of holes?
Code Quality    Lint, tests, idiomatic style
Context Endurance   Performance degradation over long tasks
Task Categories
Greenfield Projects
* Start from empty repo or minimal scaffold
* Tests brainstorming and architecture quality
* Measures: coherence of design, component boundaries, idiomatic patterns
New Features (Existing Codebases)
* Add functionality to established projects
* Tests ability to understand existing patterns and extend them
* Measures: integration quality, consistency with existing code style
Bug Fixes
* Diagnose and fix issues in existing code
* Tests debugging, root cause analysis, minimal diff solutions
* Measures: correctness, regression avoidance, fix locality
Benchmark Structure
benchmarks/
├── greenfield/      # Start from scratch
│   ├── simple/      # CLI tool, single purpose
│   ├── medium/      # Multi-component app
│   └── complex/     # Architecture decisions required
├── features/        # Add to existing codebases
│   ├── simple/      # Single-file additions
│   ├── medium/      # Multi-file, clear scope
│   └── complex/     # Cross-cutting concerns
├── bugfix/          # Diagnose and repair
│   ├── simple/      # Obvious fixes
│   ├── medium/      # Requires investigation
│   └── complex/     # Subtle/systemic issues
├── marathon/        # Tests context window management
└── recovery/        # Intentionally broken states to escape
Each task includes:
* Starting state (repo snapshot)
* Task description
* Validation criteria (tests, lint, manual checklist)
* Reference solution (optional, for scoring)
Test Corpus Sources
* Real GitHub issues (known solutions for validation)
* SWE-bench style problems
* Curated tasks at varying complexity
* "Chaos" tests - intentionally broken codebases
Measurement Challenges
* Non-determinism - Same task, different runs → need multiple trials
* Context sensitivity - Does it use existing patterns?
* Partial success - Hard to score 70% done
* Subjectivity - Architecture quality is judgment call
Implementation Ideas
* Docker containers per run for isolation
* Git snapshots for reproducible starting states
* Automated test harness for validation criteria
* Cost tracking via API usage logs
* Leaderboard / results dashboard
Orchestrator "Genes" - Composable Patterns
Treat orchestrator features as genes that can be added/removed to measure individual and combined effects:
Gene    Description
multi-agent-consensus   Multiple models agree before proceeding
cross-provider-consensus    Different providers vs same-model copies
ralph-loop  Subagent execution pattern
fresh-context   Clear context between loop iterations
auto-pilot-brainstorm   Minimize human interaction in design phase
plan-before-code    Explicit architecture step before implementation
self-review Agent reviews own code before submitting
multi-agent-review  Separate agent(s) review code
test-first  Write tests before implementation
iterative-refinement    Multiple passes vs single shot
tool-use    File ops, search, shell access
repo-mapping    Build codebase understanding first
prose-linting   Apply clarity/concision rules to docs (elements-of-style pattern)
TBD (discover more from survey)
Goal: Run ablation studies - add/subtract genes, measure impact. Find the minimal effective set and optimal combinations.
Cost optimization: Test genes against their "home turf" phases rather than exhaustive combinations:
Phase   High-value genes to test
Architecture    multi-agent-consensus, cross-provider, plan-before-code
Implementation  ralph-loop, fresh-context, repo-mapping, tool-use
Bug-fix repo-mapping, iterative-refinement
Code Review multi-agent-review, cross-provider
Documentation   prose-linting, simpler patterns may suffice
Compute advantage: Self-host open models (Llama/Mixtral/DeepSeek) for screening phase, reserve API spend for frontier model validation.
Hypotheses to Test
* H1: Cross-provider consensus (Codex × Opus × Gemini) outperforms same-model consensus on defect catch rate
* H2: Multi-agent consensus reduces "design reversals" mid-implementation vs solo agents
* H3: Fresh context Ralph loops outperform stale-context loops on marathon tasks
* H4: Consensus overhead pays for itself in reduced rework
* H5: Orchestrators with dependency-aware parallel execution achieve sub-linear wall-clock time on decomposable tasks, while naive parallelization produces merge conflicts that eliminate the time advantage
Orchestrator Patterns to Survey
Need to survey the landscape - probably missing good ideas to adapt:
* Amplifier - what's their architecture?
* Gas Town - approach?
* Original Superpowers - what did we diverge from?
* Devin / Cognition - how do they handle long tasks?
* OpenHands - open source, can inspect
* SWE-agent - academic approach
* Aider - simpler but effective patterns?
* Claude Squad - multi-instance tmux orchestration
* Mentat - ?
* Smol Developer - minimalist approach
* AutoGPT / BabyAGI - early patterns, what worked/failed?
* Claude Code (this tool) - what patterns does Anthropic use?
Next Steps
1. [ ] Survey 5-10 orchestrator patterns, document key ideas
2. [ ] Define 10 initial benchmark tasks across complexity levels
3. [ ] Create harness for running orchestrators against tasks
4. [ ] Instrument Conclave for metrics collection
5. [ ] Run baseline comparisons (including same-model vs cross-provider)
6. [ ] Publish results / methodology
Related
* Conclave (Superpowers fork)
* boxctl (could provide test tasks from real infra scripts)
* SWE-bench (prior art)

