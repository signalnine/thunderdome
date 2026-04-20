# Agentic Thunderdome

Two agents enter, one agent leaves.

Agentic Thunderdome benchmarks AI coding tools against 19 standardized programming tasks in isolated Docker containers. Each orchestrator gets a task prompt, a workspace, and a time limit. Scoring is deterministic -- automated tests and static analysis, no LLM judges. The dataset spans 6,097 scored trials across 163 orchestrator variants (9,102 total including crashes).

## Results

Composite scores ranked by Overall (average of Standard and Hard suite means). Crash trials (cost=$0, or duration <15s for local models) excluded. Entry requires 8+ standard AND 8+ hard non-crash trials.

### Tools You Can Use

Third-party orchestrators and harnesses — things you can install and run today.

| Rank | Orchestrator | Overall | Standard | Hard | Trials | $/task | Model |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | [Conclave](https://github.com/signalnine/conclave) v10 Routed | **90.4%** | 88.9% | 91.9% | 52 | $1.23 | Haiku -> Opus/Sonnet |
| 2 | [Conclave](https://github.com/signalnine/conclave) v8 (Opus) | **88.7%** | 88.5% | 89.0% | 37 | $1.45 | Opus 4.6 |
| 3 | [Conclave](https://github.com/signalnine/conclave) v8 (Sonnet) | **88.6%** | 87.2% | 89.9% | 38 | $0.82 | Sonnet 4.6 |
| 4 | [Conclave](https://github.com/signalnine/conclave) Review | **87.8%** | 87.4% | 88.2% | 139 | $1.86 | Opus 4.6 |
| 5 | [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) | **87.3%** | 84.7% | 89.9% | 57 | $1.74 | Opus 4.6 |
| 6 | [Conclave](https://github.com/signalnine/conclave) v6 (Sonnet) | **86.5%** | 85.8% | 87.2% | 84 | $1.11 | Sonnet 4.6 |
| 7 | [Conclave](https://github.com/signalnine/conclave) v6 (Opus) | **85.8%** | 86.4% | 85.2% | 82 | $2.10 | Opus 4.6 |
| 8 | [Conclave](https://github.com/signalnine/conclave) v7 Lite (Opus) | **85.6%** | 85.8% | 85.4% | 36 | $1.36 | Opus 4.6 |
| 9 | [Conclave](https://github.com/signalnine/conclave) v7 Double Review (Sonnet) | **84.4%** | 82.9% | 86.0% | 21 | $2.80 | Sonnet 4.6 |
| 10 | [Gas Town](https://github.com/steveyegge/gastown) | **83.0%** | 79.8% | 86.3% | 61 | $2.38 | Opus 4.6 |
| 11 | [GSD](https://github.com/gsd-build/get-shit-done) | **82.9%** | 84.4% | 81.5% | 57 | $1.13 | Opus 4.6 |
| 12 | [ExoMonad v2](https://github.com/tidepool-heavy-industries/exomonad) | **80.9%** | 73.5% | 88.2% | 45 | $0.75 | Opus 4.6 + Gemini |
| 13 | [Conclave](https://github.com/signalnine/conclave) v7 Lite (Sonnet) | **80.3%** | 84.1% | 76.4% | 31 | $0.71 | Sonnet 4.6 |
| 14 | [ExoMonad v1](https://github.com/tidepool-heavy-industries/exomonad) | **74.8%** | 66.8% | 82.9% | 22 | $0.84 | Opus 4.6 + Gemini |

### Harness and Model Tests

Same harness with different models, or same model through different harnesses. Tests which component drives performance.

| Orchestrator | Overall | Standard | Hard | Trials | $/task | Model |
|---|---:|---:|---:|---:|---:|---|
| v11 Qwen-routed (Neuralwatt+Sonnet) | **86.3%** | 86.6% | 86.0% | 20 | $0.74 | Haiku -> (Qwen+zen + Sonnet verify \| Sonnet v8) |
| Qwen+Sonnet-verify (Neuralwatt+Sonnet) | **83.3%** | 82.5% | 84.1% | 54 | $0.51 | Qwen3.6 zen-lite writes, Sonnet verifies/fixes (Pareto-optimal at $0.51, n=3) |
| [CRUSH](https://github.com/nicepkg/crush) (GLM5) | **81.7%** | 89.1% | 74.3% | 30 | $0.73 | GLM-5 |
| Gemini CLI | **80.9%** | 80.9% | 80.8% | 60 | $0.14 | Gemini 2.5 Pro |
| Claude Code + GLM-5.1-fast (Neuralwatt) | **75.7%** | 84.2% | 67.2% | 54 | $0.93 | GLM-5.1-FP8 |
| Zen-lite + GLM-5.1-fast (Neuralwatt) | **83.1%** | 85.2% | 80.9% | 20 | ~$1.00 | GLM-5.1-FP8 + zen prompt (7 initial timeouts discarded + re-run with 90-150min limits) |
| [CRUSH](https://github.com/charmbracelet/crush) + GLM-5.1-fast (Neuralwatt) | **64.9%** | 76.9% | 52.8% | 20 | -- | GLM-5.1-FP8 via CRUSH native Anthropic endpoint (-10.8pp vs Claude Code harness) |
| [Forge Code](https://forgecode.dev) + GPT-5.4 | **66.3%** | 72.6% | 59.9% | 20 | -- | GPT-5.4 via Forge (TermBench 2.0 leader); fast but no lift on this suite |
| [Codex](https://github.com/openai/codex) + GPT-5.4 | **74.2%** | 79.6% | 68.7% | 20 | $0.21 | GPT-5.4 via OpenAI's Codex CLI (+7.9pp over Forge on same model) |
| [Forge Code](https://forgecode.dev) + Gemini 3.1 Pro | **61.1%** | 66.3% | 55.8% | 20 | -- | Gemini 3.1 Pro via Forge; worst Forge variant (Google Gemini CLI on 2.5 Pro beats it at 80.9%) |
| [Forge Code](https://forgecode.dev) + Claude Sonnet 4.6 | **72.4%** | 85.4% | 59.4% | 20 | -- | Sonnet 4.6 via Forge (best Forge variant; but -16pp below Conclave v8 + Sonnet at 88.6%) |
| [Amplifier](https://github.com/microsoft/amplifier) (Gemini 2.5 Flash) | **75.7%** | 78.7% | 72.7% | 17 | $0.02 | Gemini 2.5 Flash |
| CRUSH (GLM-5-Turbo) | **73.7%** | 76.5% | 70.9% | 38 | $2.27 | GLM-5-Turbo |
| CRUSH (MiniMax M2.7) | **72.7%** | 75.1% | 70.4% | 39 | $0.39 | MiniMax M2.7 |
| Cerebras CLI Ralph | **72.4%** | 69.9% | 74.9% | 25 | - | gpt-oss-120b |
| CRUSH (Nemotron 120B) | **68.5%** | 66.6% | 70.5% | 67 | $2.50 | Nemotron 120B |
| CRUSH (Kimi K2.5) | **66.3%** | 72.9% | 59.8% | 64 | $0.47 | Kimi K2.5 |
| [Hermes](https://github.com/anthropics/hermes) MiMo (prompted) | **64.9%** | 62.3% | 67.5% | 18 | $0.18 | MiMo-V2-Flash |
| [Hermes](https://github.com/anthropics/hermes) MiMo | **64.3%** | 61.3% | 67.3% | 56 | $0.16 | MiMo-V2-Flash |
| CRUSH (Nemotron 120B prompted) | **63.7%** | 70.1% | 57.3% | 57 | $2.16 | Nemotron 120B |
| CRUSH (MiniMax M2.5) | **61.7%** | 71.9% | 51.6% | 66 | $0.47 | MiniMax M2.5 |
| CRUSH (GLM-4.7-Flash) | **55.9%** | 63.6% | 48.2% | 71 | $0.54 | GLM-4.7-Flash |
| FL Supervisor Pro | **45.0%** | 52.3% | 37.6% | 483 | $0.16 | Gemini 2.5 Pro |
| FL Supervisor (Opus) | **44.0%** | 50.3% | 37.6% | 382 | $0.26 | Opus 4.6 |

### Local Inference (local GPU or energy-priced equivalent, effectively free)

Models that run on a single RTX 5090 via llama.cpp or vLLM, plus Qwen3.6-35B-A3B on Neuralwatt (energy-priced at ~$0.03/task -- we used Neuralwatt for parallel capacity, but the same weights run locally). Ranked by Overall.

| Orchestrator | Overall | Standard | Hard | Trials | $/task | Model |
|---|---:|---:|---:|---:|---:|---|
| Dao + Qwen3.6 (Neuralwatt) | **76.4%** | 76.8% | 76.1% | 20 | $0.03 | Qwen3.6-35B-A3B + water/wu-wei framing |
| Zen-lite + Qwen3.6 (Neuralwatt) | **76.1%** | 78.1% | 74.2% | 57 | $0.03 | Qwen3.6-35B-A3B + meditation + TDD (best pure-Qwen config, n=3) |
| Claude Code + Qwen3.6 (Neuralwatt) | **70.3%** | 77.7% | 62.9% | 19 | $0.04 | Qwen3.6-35B-A3B (vanilla Claude Code harness) |
| [Forge Code](https://forgecode.dev) + Qwen3.6 (Neuralwatt) | **69.9%** | 75.9% | 64.0% | 20 | ~$0.03 | Qwen3.6-35B-A3B via Forge (TermBench 2.0 leader, tied with Claude Code on this suite) |
| Conclave v8 + Qwen3.6 (Neuralwatt) | **69.1%** | 77.7% | 60.5% | 20 | $0.03 | Qwen3.6-35B-A3B + v8 discipline (2 hard tasks timed out) |
| [CRUSH](https://github.com/charmbracelet/crush) + Qwen3.6 (Neuralwatt) | **65.5%** | 77.9% | 53.2% | 20 | $0.03 | Qwen3.6-35B-A3B via CRUSH native Anthropic endpoint |
| [OpenHands](https://github.com/All-Hands-AI/OpenHands) + Qwen3.6 (Neuralwatt) | **60.5%** | 66.1% | 54.8% | 20 | -- | OpenHands CLI + Qwen3.6 via LiteLLM anthropic/ route |
| [Mini-SWE-Agent](https://github.com/SWE-agent/mini-swe-agent) + Qwen3.6 (Neuralwatt) | **58.5%** | 64.5% | 52.6% | 19 | -- | Princeton's minimalist agent + Qwen3.6 |
| [Goose](https://github.com/aaif-goose/goose) + Qwen3.6 (Neuralwatt) | **54.4%** | 64.6% | 44.3% | 20 | -- | Block/AAIF Goose + Qwen3.6 (worst Qwen3.6 harness except aider) |
| CRUSH + zen-lite + Qwen3.6 (Neuralwatt) | **60.3%** | 70.4% | 50.2% | 21 | $0.03 | CRUSH + zen prompt -- zen does NOT transfer (-5.2pp vs CRUSH vanilla) |
| CRUSH Meditation (Qwen3-Coder 30B Q4_K_S) | **59.8%** | 72.2% | 47.3% | 76 | $0 | Qwen3-Coder 30B Q4_K_S (llama.cpp) |
| CRUSH (Qwen3-Coder 30B Q4_K_S) | **57.0%** | 68.7% | 45.3% | 76 | $0 | Qwen3-Coder 30B Q4_K_S (llama.cpp) |
| CRUSH (Qwen3-Coder 30B AWQ) | **55.5%** | 61.8% | 49.2% | 114 | $0 | Qwen3-Coder 30B AWQ (vLLM) |
| [pi](https://github.com/badlogic/pi-mono) + Qwen3.6 (Neuralwatt) | **55.3%** | 65.5% | 45.1% | 20 | $0.03 | Qwen3.6-35B-A3B via vanilla pi coding agent |
| CRUSH (Qwen3-Coder 30B Q5_K_M) | **54.9%** | 62.4% | 47.4% | 75 | $0 | Qwen3-Coder 30B Q5_K_M (llama.cpp) |
| Aider (Qwen3-Coder 30B Q5_K_M) | **53.7%** | 64.6% | 42.7% | 55 | $0 | Qwen3-Coder 30B Q5_K_M (llama.cpp) |
| [Aider](https://github.com/Aider-AI/aider) + Qwen3.6 (Neuralwatt) | **50.5%** | 56.0% | 44.9% | 20 | ~$0.01 | Qwen3.6-35B-A3B via aider single-pass edit mode |
| CRUSH (Qwen 3.5 32B) | **49.1%** | 55.9% | 42.4% | 59 | $0 | Qwen 3.5 32B (vLLM) |
| CRUSH (Devstral 24B) | **44.7%** | 55.3% | 34.1% | 36 | $0 | Devstral 24B (vLLM) |

### Feature Ablations

Single "genes" tested in isolation on Claude Code — each variant holds everything constant except one feature. Ranked by Overall.

| Orchestrator | Overall | Standard | Hard | Trials | $/task | Gene |
|---|---:|---:|---:|---:|---:|---|
| Plans (Opus) | **87.6%** | 86.8% | 88.3% | 57 | $1.26 | Plan before code |
| Sonnet [gstack](https://github.com/garrytan/gstack) | **87.3%** | 87.1% | 87.5% | 73 | $0.92 | "Boil the Lake" CLAUDE.md |
| Sonnet Plans | **87.3%** | 85.6% | 89.0% | 68 | $0.92 | Plan before code (Sonnet) |
| Ralph Fresh (Opus) | **87.2%** | 86.6% | 87.8% | 61 | $1.34 | Fresh-context iteration loop |
| Stacked | **86.8%** | 86.0% | 87.5% | 64 | $1.58 | Metacog + review + worktree |
| Sonnet Plans+gstack | **86.7%** | 85.1% | 88.3% | 56 | $1.17 | Plans + gstack stacked |
| Agent Teams | **86.3%** | 87.5% | 85.1% | 73 | $3.29 | Parallel teammate subagents |
| [gstack](https://github.com/garrytan/gstack) (Opus) | **86.3%** | 85.2% | 87.5% | 57 | $1.32 | "Boil the Lake" CLAUDE.md |
| Claude Code Branch | **85.8%** | 87.4% | 84.2% | 41 | $1.11 | `git checkout -b main` |
| Claude Code NoGit | **85.0%** | 87.2% | 82.7% | 41 | $1.00 | Remove .git directory |
| Tango and Cash | **84.8%** | 83.3% | 86.4% | 59 | $1.10 | Opus plans, Gemini implements |
| Gas Station | **84.6%** | 88.5% | 80.6% | 58 | $1.08 | Context injection + worktree |
| Conclave Design | **84.0%** | 86.6% | 81.5% | 47 | $1.45 | Pre-implementation design review |
| **Claude Code (Opus 4.6)** | **84.0%** | 88.0% | 80.0% | 35 | $1.18 | **Baseline (no gene)** |
| Self-Review (Opus) | **81.9%** | 86.1% | 77.8% | 19 | $1.23 | System prompt self-review |
| Verify (Opus) | **80.8%** | 86.0% | 75.7% | 19 | $0.94 | Verification gate |
| [Caveman](https://juliusbrussee.github.io/caveman/) (Opus 4.7) | **80.6%** | 79.9% | 81.2% | 20 | $3.30 | Output-compression directive (brevity prompt) |
| Claude Code Worktree | **80.0%** | 83.8% | 76.2% | 41 | $1.00 | Git worktree workspace |
| Debug (Opus) | **77.3%** | 84.6% | 70.0% | 28 | $1.16 | Systematic debugging skill |
| Claude Code (Opus 4.7, no discipline) | **74.6%** | 70.4% | 78.8% | 19 | $3.34 | Model upgrade alone, bare prompt |

<details>
<summary><strong>Metacog Ablations</strong> — 16 system prompt variants, all Opus 4.6 (click to expand)</summary>

Each variant injects a different metacognitive reframing into vanilla Claude Code. All cluster between 80-86% — *any* structured discipline matters more than the specific prompt. Forced Inversion beats letting Claude choose its own stratagem (free-choice scores worst at 80.2%).

| Variant | Standard | Hard | Overall | Trials | $/task |
|---|---:|---:|---:|---:|---:|
| Metacog Inversion | 85.4% | 86.4% | **85.9%** | 66 | $1.03 |
| Metacog Banishing | 86.2% | 83.8% | **85.0%** | 19 | $1.05 |
| Metacog Pivot | 84.5% | 85.1% | **84.8%** | 59 | $0.98 |
| Metacog Fool | 84.9% | 84.0% | **84.5%** | 20 | $1.23 |
| Metacog Invocation | 84.8% | 83.7% | **84.2%** | 57 | $1.32 |
| Metacog Gift | 83.3% | 84.8% | **84.0%** | 18 | $1.42 |
| Metacog | 88.0% | 79.5% | **83.7%** | 58 | $1.17 |
| Metacog Reset | 85.7% | 80.2% | **82.9%** | 20 | $1.68 |
| Metacog Drift | 87.0% | 78.4% | **82.7%** | 19 | $1.30 |
| Metacog Error | 84.8% | 80.5% | **82.7%** | 57 | $1.42 |
| Metacog Veil | 85.4% | 79.8% | **82.6%** | 19 | $1.16 |
| Metacog Stack | 85.7% | 79.1% | **82.4%** | 19 | $1.29 |
| Metacog Mirror | 83.6% | 78.9% | **81.2%** | 19 | $1.41 |
| Metacog Sacrifice | 80.8% | 80.6% | **80.7%** | 19 | $1.16 |
| Metacog Anchor | 85.6% | 75.7% | **80.6%** | 19 | $0.92 |
| Metacog Scrying | 87.3% | 72.6% | **80.0%** | 19 | $1.32 |

</details>

<details>
<summary><strong>Zen Meditation Experiment</strong> -- metacognitive "meditate" primitive across 3 iterations (click to expand)</summary>

Three iterations of a zen stratagem that reframes the agent's mindset before coding. v1: base zen prompt. v2: added TDD discipline. v3: added a "meditate" primitive (objectless awareness before acting). All Sonnet 4.6 unless noted, 19 tasks each.

| Variant | Standard | Hard | Overall | Trials | $/task | What changed |
|---|---:|---:|---:|---:|---:|---|
| Zen v1 (Sonnet) | 77.8% | 85.5% | **81.7%** | 19 | $0.57 | Base zen reframing |
| Zen v2 (Sonnet) | 76.8% | 83.8% | **80.3%** | 19 | $0.85 | + TDD discipline (-1.4pp) |
| Zen v3 (Sonnet) | 82.4% | 88.7% | **85.6%** | 19 | $0.73 | + meditate primitive (+5.3pp) |
| Zen v3 (Opus) | 87.4% | 87.4% | **87.4%** | 18 | $1.30 | Opus model (+1.8pp, +78% cost) |
| Routed Stratagem (Sonnet) | 96.6% | 78.3% | **87.4%** | 38 | $0.73 | Haiku routes to best stratagem per category |
| v8 Combined (Sonnet) | 87.2% | 89.9% | **88.6%** | 38 | $0.82 | Baseline for comparison |

Zen v3 is the strongest zen variant at 85.6% but trails the v8 methodology baseline by 3pp. The meditate primitive added +5.3pp over v2, mostly through standard-suite gains (+5.6pp) where implementation completeness improved. Hard tasks gained +4.9pp from better reasoning/hard scores (91.3% vs 75.9% in v2).

Per-category highlights (v3 Sonnet vs v8 baseline): marathon +13.9pp (75.6% vs 61.7%), greenfield/simple +10.3pp (88.8% vs 78.5%), reasoning/hard +1.8pp (91.3% vs 89.5%). But greenfield/complex -19.4pp (60.9% vs 80.3%) and ambiguity/hard -16.8pp (59.6% vs 76.4%) -- meditation hurts tasks requiring aggressive exploration. The ambiguity regression is driven by coverage (93.8% -> 82.2%) and code metrics (100% -> 70%), not hidden test performance (identical at 21.2%).

v2 was a regression from v1 -- adding TDD discipline without the meditate primitive hurt greenfield/simple (32.3% vs 60.0%) and increased cost 49%. The meditate primitive was the key ingredient, not the discipline scaffolding.

**Routed stratagem** uses Haiku to classify each task's category, then routes to the best-performing metacog stratagem for that category (based on the 16-stratagem Opus ablation data above). Routing table: algorithmic->fool, ambiguity->scrying, reasoning->mirror, greenfield/simple->drift, greenfield/complex->veil, marathon->scrying, default->fool. Result: 87.4% at $0.73/task -- +1.8pp over zen v3 and slightly cheaper, but -1.2pp below v8 baseline. Haiku classification is noisy: 3/38 trials got essay-length responses instead of labels, beam-splitter (reasoning) was misclassified as greenfield, and the mirror stratagem was never triggered. Standard-suite scores (96.6%) are excellent but hard-suite (78.3%) lags v8 by 11.6pp. Routing adds complexity without clear benefit over simpler approaches.

</details>

<details>
<summary><strong>Meditation Prompt on Local Models</strong> -- does zen framing transfer to Qwen3-Coder? (click to expand)</summary>

The zen meditation experiment above showed mindset reframing helps Claude. Does it transfer to non-Claude models running locally? We adapted the meditation prompt into a CRUSH.md system prompt ("The Way of Calm Precision") and tested it against the baseline CRUSH.md on Qwen3-Coder 30B Q4_K_S via llama.cpp on a single RTX 5090. 76 paired trials per orchestrator (4 trials x 19 tasks).

| Variant | Standard | Hard | Overall | Trials | Tokens/task |
|---|---:|---:|---:|---:|---:|
| CRUSH Meditation | 72.2% | 47.3% | **59.8%** | 76 | 1.82M |
| CRUSH Baseline | 68.7% | 45.3% | **57.0%** | 76 | 2.61M |
| Delta | +3.6pp | +2.0pp | **+2.8pp** | | 0.70x |

Statistical tests: paired t-test on 76 trial pairs gives t=2.03, p=0.046 (significant). Paired t-test on 19 task means gives t=1.25, p=0.23 (not significant). Wilcoxon signed-rank gives p=0.12 (not significant). Cohen's d = 0.23 (small effect).

The effect is real but modest. Meditation wins 8 tasks, loses 5, ties 6. Biggest wins: beam-splitter (+27pp), constraint-scheduler (+20pp). Biggest losses: plugin-marketplace (-13pp), reactive-spreadsheet (-9pp). The 30% token reduction is the more reliable finding -- the meditation prompt produces more focused, less verbose agent behavior regardless of whether final scores improve.

</details>

<details>
<summary><strong>Conclave v8 Methodology Ablations</strong> -- 6-step methodology dissected on Sonnet 4.6 (click to expand)</summary>

The v8 methodology has six steps: (1) Understand, (2) Contract, (3) TDD, (4) Boil the Lake, (5) Verify against contract, (6) Adversarial self-review. Two ablation designs: **gene removal** (remove one step from the full stack) and **gene isolation** (emphasize one step, weaken others). All Sonnet 4.6 unless noted.

**Gene Removal** -- each variant removes one step from the full v8 stack:

| Variant | Overall | Standard | Hard | Trials | $/task | Gene removed | Delta |
|---|---:|---:|---:|---:|---:|---|---:|
| v8 Combined (Sonnet) | **88.6%** | 87.2% | 89.9% | 38 | $0.82 | None (baseline) | -- |
| v8 No-Boil (Sonnet) | **87.7%** | 87.1% | 88.3% | 47 | $0.89 | Boil the Lake | -0.9pp |
| v8 No-TDD (Sonnet) | **87.6%** | 84.1% | 91.1% | 47 | $0.80 | TDD | -1.0pp |
| v8 No-Review (Sonnet) | **87.1%** | 85.7% | 88.4% | 85 | $0.78 | Self-review | -1.5pp |
| v8 No-Contract (Sonnet) | **87.0%** | 87.0% | 87.0% | 46 | $0.89 | Contract | -1.6pp |
| v8 Bare (Sonnet) | **83.4%** | 82.0% | 84.7% | 50 | $0.69 | All methodology | -5.2pp |

The genes are roughly additive: boil (0.9) + TDD (1.0) + review (1.5) + contract (1.6) = 5.0pp, closely matching the 5.2pp bare-to-combined gap. No major synergy effects -- each gene contributes independently.

Contract is the most valuable single gene at 1.6pp, followed by self-review at 1.5pp. TDD and boil-the-lake contribute ~1pp each. All four genes pull their weight.

The bare variant is revealing: even with no methodology beyond "understand first", Sonnet scores 83.4% -- higher than many structured Opus orchestrators. The model's baseline capability is strong; methodology adds the last 5pp of polish.

**Gene Isolation** -- each variant emphasizes one step with weaker others:

| Variant | Overall | Standard | Hard | Trials | $/task | What changed |
|---|---:|---:|---:|---:|---:|---|
| v8 Ralph (Sonnet) | **87.9%** | 86.5% | 89.4% | 21 | $0.93 | Control for eval variant |
| v8 Contract (Opus) | **87.5%** | 86.7% | 88.3% | 38 | $1.60 | Contract emphasis, weaker TDD |
| v8 Eval (Sonnet) | **87.2%** | 86.6% | 87.7% | 38 | $0.78 | Two-pass with evaluator diagnosis |
| v8 No-Review Ralph (Sonnet) | **87.2%** | 89.5% | 85.0% | 43 | $0.83 | No-Review + fresh-context retry loop |
| v8 Contract (Sonnet) | **86.5%** | 83.5% | 89.6% | 38 | $0.74 | Contract emphasis, weaker TDD |
| v8 TDD-Hard (Sonnet) | **86.4%** | 86.7% | 86.1% | 38 | $0.84 | TDD emphasis, no contract |
| v8 TDD-Hard (Opus) | **83.4%** | 87.5% | 79.3% | 37 | $1.62 | TDD emphasis, no contract |

**Other variants:**

| Variant | Overall | Standard | Hard | Trials | $/task | What changed |
|---|---:|---:|---:|---:|---:|---|
| v10 Haiku-Routed | **90.4%** | 88.9% | 91.9% | 52 | $1.23 | Haiku classifies -> Opus (hard) / Sonnet (easy) |
| v9 Review Slim (Sonnet) | **87.5%** | 92.2% | 82.9% | 19 | $1.72 | Two-pass: v8 then hostile review+fix (-1.1pp, +$0.90) |
| v8 Combined High Effort (Sonnet) | **87.3%** | 88.8% | 85.7% | 38 | $0.80 | `--effort high` reasoning mode (-1.2pp) |
| v8 Outcomes (Sonnet) | **87.7%** | 87.2% | 88.2% | 34 | $0.74 | Deterministic iteration loop |

The two-pass evaluator (v8 Eval) performs no better than removing self-review entirely -- external diagnosis does not outperform self-correction. v9 Review Slim confirms this: a hard-wired hostile review+fix pass after full v8 implementation scores 87.5% at $1.72 -- losing 1.1pp while more than doubling cost. The second pass finds and "fixes" things that weren't broken. The cheapest competitive config is v8 No-Review at $0.78 and 87.1%, which beats every Opus ablation variant at half the cost.

Adding a fresh-context retry loop (ralph) to No-Review produces 87.2% -- within noise of the 87.1% baseline. Retry helps on standard tasks (+3.8pp) but hurts on hard tasks (-3.4pp). On reasoning-heavy problems like circuit-debugger, a wrong first approach pollutes the workspace and subsequent retries dig deeper into the wrong hole. Iteration without insight is not improvement.

The outcomes variant uses a harness-enforced iteration loop inspired by Anthropic's Managed Agents "Outcomes" pattern: initial pass with v8 (no self-review), then up to 2 more iterations driven by deterministic validation feedback (test results, build errors, lint output) in a fresh context window. At 87.7% it outperforms no-review (87.1%) by 0.6pp but trails self-review (88.6%) by 0.9pp. The isolated grading helps -- fresh-context feedback catches things the agent missed -- but same-context introspection still wins. The agent's ability to reason about its own implementation choices is more valuable than external test feedback.

Increasing reasoning effort (`--effort high`) also hurts: 87.3% vs the 88.6% medium baseline (-1.2pp). The methodology is a recipe -- following it precisely matters more than thinking deeply about each step. Extra reasoning doesn't help when the bottleneck is execution discipline, not insight.

Haiku-based model routing (v10) scores highest at 90.2% but barely routes -- Haiku classifies 17/19 tasks as HARD, sending almost everything to Opus. Only phantom-invoice and time-tracker get Sonnet. The result is effectively "Opus with no-review v8 prompt" at a small discount ($1.20 vs $1.45). The +1.6pp over v8 Sonnet comes from Opus quality on hard tasks (91.9% vs 89.9%), not from smart routing. A smarter classifier that routes more tasks to Sonnet could preserve most of the quality gain at lower cost.

</details>

## What We Learned

### Discipline beats complexity

The gap from vanilla Claude Code (84.0%) to the best orchestrator (90.4%) is 6.4 percentage points. The v8 methodology -- a 6-step system prompt (understand, contract, TDD, complete implementation, verify, self-review) -- captures most of that gap with no plugins, no multi-agent overhead, and runs on Sonnet at 88.6% for $0.82/task. Haiku-routed model selection (v10) pushes to 90.4% at $1.23 by routing hard tasks to Opus.

Every discipline gene helps. Self-review, TDD, plan-before-code, verification gates -- all lift scores above vanilla. The specific discipline matters less than having one at all. Sixteen metacog variants with wildly different system prompts all land between 80-86%.

Output-compression directives don't substitute for discipline. [Caveman](https://juliusbrussee.github.io/caveman/) (drop articles, fragments OK, terse technical prose) on Opus 4.7 scored 80.6% overall vs 84.0% for vanilla Opus 4.6 -- brevity alone doesn't improve codegen accuracy. Caveman's public claim ("brevity improves accuracy by 26pp") does not replicate on these tasks. Token savings were real (12 turns avg vs 16-19 for discipline orchestrators), but the standard suite dropped -8.1pp.

Model upgrades don't substitute for discipline either. Vanilla Claude Code on Opus 4.7 scored 74.6% overall (70.4% std, 78.8% hard) -- **-9.4pp below vanilla Opus 4.6** (84.0%). Opus 4.7 without scaffolding underperforms 4.6 across the board except hard tasks (+1.2pp) where hidden thinking tokens still pull weight. With v8 methodology Opus 4.7 recovers to 86.3% -- still below v8 + Opus 4.6 (88.7%). Cost is 2.8x higher ($3.34 vs $1.18 vanilla) because 4.7 bills ~50K hidden thinking tokens per task that never surface in `stream-json` usage fields. Net: 4.7 on bare Claude Code is a cost and accuracy regression; use 4.6 unless you're running a discipline-heavy orchestrator that already structures the thinking budget.

Methodology components stack additively. Gene removal ablations show each step's independent contribution: contract (-1.6pp when removed), self-review (-1.5pp), TDD (-1.0pp), boil-the-lake (-0.9pp). These sum to 5.0pp -- closely matching the 5.2pp gap between bare Sonnet (83.4%) and full v8 (88.6%). No synergy effects: each gene helps regardless of what other genes are present. A two-pass evaluator (separate diagnostic agent) adds nothing over self-review. The lesson: simple introspective loops beat complex multi-pass architectures.

Multi-agent consensus adds nothing measurable. We tested three configurations: pure skill text (no binary), Claude-only consensus, and true multi-provider consensus (Claude + Gemini + Codex). All converged within 2pp. The skill text drives the value. The consensus mechanism is noise.

Retry loops don't help either. The ralph fresh-context loop -- which runs `claude -p` up to 5 times per task with a clean context each attempt -- adds +0.1pp overall (87.2% vs 87.1% No-Review baseline, n=43). On standard tasks ralph gains +3.8pp, but on hard tasks it loses -3.4pp. The pattern: retry helps on simpler tasks where a second attempt can fix mechanical errors, but hurts on reasoning-heavy tasks where a wrong first approach leaves workspace artifacts that mislead subsequent attempts. T17 (circuit-debugger) drops hardest -- agents that simulate instead of recognizing structure keep simulating on retry.

### The model is not the bottleneck — the harness is

Same GLM-5 model, same weights, same API, three different harnesses:

| Harness | Overall | Cost |
|---|---:|---:|
| [CRUSH](https://github.com/nicepkg/crush) | **81.7%** | $0.73 |
| [oh-my-pi](https://github.com/can1357/oh-my-pi) | **63.8%** | ~$0 |
| Claude Code protocol | **57.8%** | $0.10 |

The spread is 24 points. CRUSH won because its loop is simple: read the task, write code, run tests, fix failures, repeat. GLM-5 follows that recipe reliably. Claude Code lost because its agentic protocol — multi-turn tool chains, subagent delegation, structured content blocks — demands capabilities GLM-5 cannot sustain across 50+ turns.

Same Qwen3-Coder 30B model, same GPU, two quantizations: AWQ on vLLM (55.5%) edges Q5_K_M on llama.cpp (54.9%). The inference engine matters as much as bit depth.

Dense thinking models need fast harnesses. Deckard 40B at 50 tok/s timed out on every CRUSH task but scored 57.5% standard via Aider's single-pass approach in two minutes per task. For slow models, one good shot beats iterative retry.

Discipline prompts don't automatically transfer to smaller models. We ran v8 combined (the 6-step contract/TDD/review prompt that lifts Claude to #2 overall at 88.7%) on Qwen3.6-35B-A3B via Neuralwatt. Result: **69.1% overall, -1.2pp below vanilla Qwen3.6 (70.3%)**. The per-task picture was mixed — some huge wins (reactive-spreadsheet +53pp, analytics-dashboard +37pp, constraint-scheduler +36pp) but two hard tasks timed out at the 40-minute limit because the contract-first discipline made the model slower than it could afford. Time-tracker dropped -45pp because v8's "write a CONTRACT.md first" caused the model to over-structure a simple task. v8's component weights (contract +1.6pp, review +1.5pp, TDD +1.0pp, boil +0.9pp in the Claude ablation) depend on a model that can execute the discipline within the time budget; for a mid-range open-weights model, the discipline overhead eats into effective iteration time.

But zen framing transfers dramatically. We built zen-lite -- meditation prologue ("release urgency, attend to what the code needs, quality emerges from stillness") + TDD (write failing test, then code) + verify loop. No contract, no boil-the-lake, no self-review. At n=3 (53 trials), result: **77.2% overall, +6.9pp over vanilla Qwen3.6 (70.3%) and +13.4pp on hard suite (62.9% → 76.3%)**. Standard suite near-perfect stable (77.7% → 78.1%). At n=1 the hard-suite lift looked larger (80.1%) but +13pp survives the backfill. The per-task lift is concentrated on reasoning-heavy work where Qwen3.6 naturally flails without structure. Ablation proved the zen framing does the work, not the TDD -- a v8-no-contract variant (TDD + boil + review without zen) scored 62.2%, -8.1pp below vanilla. CRUSH-minimal (the simple "read, code, test, fix" loop that tripled Qwen 3.5 32B) also regressed to 61.0%. The calm, deliberate tone is what Qwen3.6 needs; additional structure on top is overhead. For an open-weights 35B model, a light-touch meditation prompt beats a heavyweight 6-step methodology by nearly 10 points.

Harness matters too, and Claude Code's protocol is sturdier than pi's minimalist approach. We ran vanilla pi (the [upstream coding agent](https://github.com/badlogic/pi-mono), not oh-my-pi) against the same Qwen3.6 endpoint. Result: **55.3% overall, -15pp below vanilla Claude Code**. Pi nailed five simple tasks at 1.0 (debug-nightmare, financial-ledger, ssg-toolkit, monorepo-disaster, phantom-invoice) but hard-suite scores collapsed (45.1% hard vs 62.9% on Claude Code). Pi exposes only four tools -- read, bash, edit, write -- and a terse default system prompt. For a mid-range open-weights model, Claude Code's richer tool surface (TodoWrite, Grep, Glob, parallel Bash) and structured system prompt give the model more scaffolding to work with. Qwen3.6 benefits from that structure; minimalism hurts it on hard tasks. Note: pi's compatibility with vLLM required patching our proxy to rewrite OpenAI's newer `"role": "developer"` (which pi uses) back to the legacy `"role": "system"` that vLLM expects -- otherwise every request returned 400.

The calm-framing lift generalizes beyond zen. We built a parallel "Dao-lite" adapter with different imagery (wu wei, water flowing around obstacles, uncarved block, empty vessel) and the same structural bones (read → test-first → verify). Result: **76.4% overall** on Qwen3.6 -- within 0.3pp of zen-lite at n=1 (both at n=1 runs: dao 76.4% vs zen 79.4%; zen regressed to 76.1% at n=3, bringing them effectively even). The effect is not about zen Buddhism specifically -- it's about calm, deliberate framing as a class. Any prompt that tells a mid-range open-weights model "release urgency, sit with what is, write one small truth at a time" appears to help similarly.

The best cost/quality point so far: **Qwen3.6 writes, Sonnet verifies** at 83.3% for $0.51/task at n=3 (54 trials). We ran the same Qwen3.6-Neuralwatt endpoint for phase 1 (zen-lite prompt for writing + initial test coverage), then a Sonnet pass for phase 2 (read the diff, run the verification suite, fix anything broken). Sonnet does not add features or rewrite; it just gets the workspace to green. The blend joins the Pareto frontier at $0.51, between Gemini CLI ($0.14, 80.9%) and Conclave v8 Sonnet ($0.82, 88.6%). Adding Haiku routing (send hard tasks directly to Sonnet v8, send easy tasks to Qwen+verify) lifts the hybrid to 86.3% but raises cost to $0.74 -- not Pareto because conclave-v8-contract-sonnet hits 86.5% at the same $0.74. **The cheap-writer-plus-expensive-reviewer pattern is where the Pareto win lives**, not the routing. Regression from n=1 to n=3 was -1.5pp (84.8% → 83.3%), meaningfully smaller than pure-Qwen prompts which lost ~3pp at n=3. Sonnet's verify pass stabilizes variance in addition to lifting scores.

The tool-surface penalty is model-dependent and gets worse for more capable models. CRUSH loses Qwen3.6 about -5pp vs Claude Code (70.3 → 65.5), but loses GLM-5.1-fast about -11pp (75.7 → 64.9). GLM-5.1 is a 600B+ param model; Qwen3.6 is 35B active. Claude Code's richer tools (TodoWrite for state, Grep/Glob for exploration, parallel Bash for verification) matter more when the model has more capability to channel into structured iteration. CRUSH + GLM-5.1 lands at basically the same score as CRUSH + Qwen3.6 (64.9% vs 65.5%) -- same harness, same ceiling, model capability can't punch through the tool constraint.

Zen on GLM-5.1 is a time-budget story, not a quality story. GLM-5.1 + zen-lite initially scored **68.2% overall** with 7 of 19 tasks hitting the default 45-60 minute timeouts. After discarding the timeouts and re-running with 90-150 minute limits, the score jumped to **83.1% (85.2% std, 80.9% hard)** -- a +14.9pp correction. The model can solve the hard tasks when given time; zen's deliberate cadence on GLM-5.1's slower per-turn latency (32 tok/s vs Qwen3.6's 64 tok/s) just multiplies wall-clock time. One task still never completed even at 2.5 hours: bench-circuit-debugger scored 0.29 after 82 minutes. **Zen's lift requires both the right tools (Claude Code's surface) AND enough time budget** -- increase the time limit and GLM-5.1 + zen lands competitive. Methodology note: discarding timeout artifacts from orchestrators that prove capable-given-time is how we treat "failure to finish" vs "failure to solve"; see also `crush-qwen3coder-local-meditate` where similar timeout replacement lifted scores +2.8pp.

Forge Code is the TermBench 2.0 leader but ties Claude Code on this suite. Forge + Qwen3.6 scored **69.9%** vs Claude Code + Qwen3.6 at 70.3% -- a wash (-0.4pp overall, +1.1pp hard). Forge + GPT-5.4 scored **66.3%** -- no lift from the more capable model. The TermBench 2.0 leaderboard rewards different properties (tool-call patterns, agentic subroutines, command-generation) than our suite rewards (test-coverage-plus-implementation-correctness on open-ended greenfield). Forge's real win here is speed: most tasks completed in 3-6 min vs Claude Code's ~10 min, and a full 19-task suite at parallel=19 wrapped in ~30 min wall-clock. **Different harnesses are optimized for different benchmark shapes**; TermBench 2.0 leadership does not automatically translate to score lift on programming tasks with rich test suites and hidden validators.

Forge + Gemini 3.1 Pro landed lower than Forge on any other model we tried: **61.1%** overall (66.3% std, 55.8% hard). Gemini 3.1 Pro is the flagship preview and T1 smoke scored 0.83 -- but on greenfield hard tasks (reactive-spreadsheet, factory-reset, beam-splitter) it collapsed to 0.20-0.22. Google's own Gemini CLI runs the same-class Gemini 2.5 Pro at **80.9%** on this suite -- a +19.8pp gap for the same model family. Forge's architecture clearly doesn't cooperate with Gemini 3.x's tool-calling conventions.

Forge + Sonnet is the best Forge variant we've measured but still leaves 16pp on the table vs Conclave v8 + Sonnet. **Forge + Claude Sonnet 4.6: 72.4% (85.4% std, 59.4% hard)**. Standard tasks near-perfect -- 5 at 1.00, phantom-invoice at 0.98, ecommerce/time-tracker/plugin-marketplace at 0.91-0.96. Hard suite collapsed on 4 tasks at 0.20 (factory-reset, circuit-debugger, structural-merge, task-queue). Same Sonnet model runs at **88.6% in Conclave v8** on the same suite -- a 16pp gap from methodology alone. Pattern: Forge finishes fast (most tasks 3-6 min) but doesn't iterate enough on reasoning-heavy hard tasks where Conclave's test-first-then-verify loop pays off. **Forge × Sonnet confirms the earlier finding**: TB2.0 leadership doesn't translate to this suite regardless of which model you put in.

Terminal-Bench 2.0 leaderboard harnesses underperform on this suite. We tested three Qwen3.6 harnesses from the TB2.0 rankings that we hadn't seen before: OpenHands (ex-OpenDevin, TB2.0 #50), Mini-SWE-Agent (Princeton, #68), and Goose (Block/AAIF, #45). All three landed below Claude Code + Qwen3.6 (70.3%): **OpenHands 60.5%, Mini-SWE 58.5%, Goose 54.4%**. The pattern is consistent with our earlier finding that TB2.0 rewards different properties than this suite (test-coverage-plus-hidden-validators) -- harnesses optimized for TB2.0's command-generation tasks don't automatically transfer. Goose was the weakest: 0.00 agent-tests coverage on multiple greenfield tasks, same failure mode as aider's single-pass edit style. All three were easy to get running (pip / tar.bz2 binary install), so the regression isn't about config tuning -- it's about how they drive tools.

Codex outperforms Forge on the same model. OpenAI's official Codex CLI scored **74.2% with GPT-5.4** -- **+7.9pp over Forge + GPT-5.4** (66.3%). Both are fast (Codex averaged 3 min per task including reasoning) and both use GPT-5.4's native responses API, but Codex writes more tests on greenfield tasks, which this suite's greenfield scoring rewards heavily (agent_tests x coverage is 31% of greenfield weight). The gap is entirely harness behavior -- same model, same endpoint. Caveat: one task (reactive-spreadsheet) hung at the 60-minute timeout scoring 0.20; without that Codex would have been ~76.3%. Still, $0.21/task average cost with extensive prompt caching (usually ~80% cache hit rate on Codex's second turn onward) makes GPT-5.4 via Codex a viable budget frontier option at $0.21 -- between Gemini CLI ($0.14, 80.9%) and Qwen+Sonnet-verify ($0.51, 83.3%).

CRUSH lands between Claude Code and pi. Running CRUSH via its native Anthropic-compatible provider type (no proxy, direct to Neuralwatt's `/v1/messages` with a browser User-Agent header to bypass Cloudflare WAF) gave **65.5% overall** on Qwen3.6 -- better than pi (+10pp), worse than Claude Code (-5pp). Zero crashes, zero timeouts. CRUSH's simple test-driven loop matches well-specified tasks well but its minimal tool surface (read/bash/edit/write, same as pi) leaves hard-suite scores at 53.2%.

Zen does not transfer across harnesses. Running the same zen-lite prompt through CRUSH regressed scores to **60.3% overall (-5.2pp vs CRUSH vanilla)**. Big wins on beam-splitter (+0.32) but bigger losses elsewhere: permission-maze -0.33, ecommerce-backend -0.26 (a standard task that vanilla CRUSH handled at 0.91), collab-server -0.22, task-queue -0.21. The interpretation: zen's calm, deliberate framing demands tools that support fine-grained iteration (TodoWrite for tracking contract criteria, Grep/Glob for exploration, parallel Bash for verification). With CRUSH's minimal tool surface, "release urgency" and "one small truth at a time" becomes paralysis rather than precision. The prompt lifts Claude Code because Claude Code's tools can execute the deliberate cadence the prompt asks for; CRUSH can't. **Prompt wins depend on having the tools to execute the prompt.**

### Sonnet with discipline matches Opus without it

Conclave v8 on Sonnet (88.6%, $0.82) ties v8 on Opus (88.7%, $1.45) at 43% less cost -- and beats every prior Opus orchestrator including Conclave Review (87.8%, $1.86). Sonnet gstack (87.3%, $0.92) and Sonnet Plans (87.3%, $0.92) beat vanilla Claude Code Opus (84.0%, $1.18) at 22% less cost. The right methodology makes the cheaper model win.

### Hard tasks reveal what standard tasks hide

Standard-suite spread among top orchestrators: ~8pp. Hard-suite spread: 56pp. Standard tasks test pattern implementation; hard tasks test whether the agent discovers novel algorithms.

T17 (circuit-debugger) is the sharpest differentiator. Agents that simulate circuits cap at 25%. Agents that recognize structural properties reach 92%. No amount of iteration compensates for the wrong approach.

T14 (financial-ledger) is the great equalizer — every orchestrator scores 96-100%. T15 (permission-maze) remains the hardest non-crashing task (58-80%) because the spec is deliberately vague and agents that assume instead of exploring fail.

### Scores drop with more data

Every orchestrator scored higher at n=1 than at n=3+. Agent Teams dropped from 90.6% to 86.3%. Sonnet Plans+gstack dropped from 90.1% to 86.7%. Plans hard dropped from 90.7% to 88.3%.

Trust scores backed by 50+ trials, not 8. The leaderboard stabilized only after we backfilled n=3 across the board.

### Cost and quality decouple at the top

The Pareto frontier spans three orders of magnitude in cost:

**$0.02** Amplifier Gemini 2.5 Flash (75.7%) -> **$0.14** Gemini CLI (80.9%) -> **$0.51** Qwen+Sonnet-verify (83.3%) -> **$0.82** Conclave v8 Sonnet (88.6%) -> **$1.23** Conclave v10 Routed (90.4%)

The sharpest knee is at $0.51. Qwen+Sonnet-verify uses Qwen3.6 (Neuralwatt, energy-priced) to write an initial implementation with the zen-lite prompt, then hands off to Sonnet for a verification pass that reads the diff, runs tests, and fixes whatever isn't green. The hybrid lands at 83.3% for $0.51/task at n=3 (54 trials). Nothing between $0.14 and $0.74 scores higher. Above it, $0.31 more buys +5.3pp via full-pipeline Sonnet v8 (88.6%), then $0.41 more buys +1.8pp via Haiku-routed model selection (v10 at 90.4%). The cheap-writer-plus-expensive-reviewer pattern may be generalizable: any time a capable but faster/cheaper model can produce an 80% solution, a frontier-model verify pass closes the remaining gap for a fraction of running the frontier model end-to-end.

### Local models closed most of the gap

A year ago the story was "local models lag frontier APIs by 30-40pp." It's now 13pp and shrinking. Qwen3.6-35B-A3B (runs on a single RTX 5090) with a zen-lite prompt hits **76.1% at n=3** -- competitive with many hosted Sonnet orchestrators. Plug that same model into the cheap-writer-plus-expensive-reviewer pattern (Qwen writes, Sonnet verifies) and it lands on the Pareto frontier at $0.51.

Key progressions:
- **Qwen 3.5 32B (early 2026)**: 49% via CRUSH, near-zero via Claude Code protocol. The [CRUSH](https://github.com/nicepkg/crush) system prompt nearly tripled it from ~20% to 49%. Harness mattered more than model.
- **Qwen3-Coder 30B**: 54-60% at $0/task. Meditation-adapted CRUSH.md pushed Q4_K_S to 59.8% (+2.8pp, p=0.046 paired t-test on 76 trial pairs, non-parametric tests don't reach significance).
- **Qwen3.6-35B-A3B (current)**: 70.3% vanilla, **76.1% with zen-lite, 76.4% with Dao framing** -- effectively tied. The calm-framing lift is a class effect, not specific to zen.

The prompts learned on prior Qwen generations transfer with bigger absolute deltas: Qwen3-Coder got +2.8pp from meditation; Qwen3.6 gets +6.9pp from zen-lite (+13.4pp hard). Prompt discoveries compound with model capability. The best open-weights number we've measured on this suite is now 76.4% -- far from the 90.4% frontier but closer every iteration.

[Hermes](https://github.com/anthropics/hermes) + MiMo-V2-Flash (Xiaomi's 309B MoE, 15B active) scores 64.3% at $0.16/task — the cheapest hosted option with full-suite data and competitive hard-task performance (67.3%).

## Cost Efficiency

All leaderboard orchestrators sorted by cost. **Bold** = Pareto-optimal (no orchestrator scores higher at equal or lower cost). Metacog variants omitted — all fall between $0.92-$1.68 at 80-86%.

| Orchestrator | Overall | $/task | Pareto |
|---|---:|---:|:---:|
| CRUSH (Qwen 3.5 32B) | 49.1% | $0.00 | |
| Aider (Qwen3-Coder 30B Q5_K_M) | 53.7% | $0.00 | |
| CRUSH (Qwen3-Coder 30B Q5_K_M) | 54.9% | $0.00 | |
| CRUSH (Qwen3-Coder 30B) | 55.5% | $0.00 | |
| CRUSH (Qwen3-Coder 30B Q4_K_S) | 57.0% | $0.00 | |
| CRUSH Meditation (Qwen3-Coder 30B Q4_K_S) | 59.8% | $0.00 | |
| Cerebras CLI Ralph | 72.4% | $0.00 | |
| **Amplifier (Gemini 2.5 Flash)** | **75.7%** | **$0.02** | **best <$0.14** |
| Conclave v8 + Qwen3.6 (Neuralwatt) | 69.1% | $0.03 | |
| CRUSH + zen-lite + Qwen3.6 (Neuralwatt) | 60.3% | $0.03 | |
| CRUSH + Qwen3.6 (Neuralwatt) | 65.5% | $0.03 | |
| Dao + Qwen3.6 (Neuralwatt) | 76.4% | $0.03 | |
| pi + Qwen3.6 (Neuralwatt) | 55.3% | $0.03 | |
| Zen-lite + Qwen3.6 (Neuralwatt) | 76.1% | $0.03 | |
| Claude Code + Qwen3.6 (Neuralwatt) | 70.3% | $0.04 | |
| **Gemini CLI** | **80.9%** | **$0.14** | **best <$0.51** |
| Hermes MiMo | 64.3% | $0.16 | |
| FL Supervisor Pro | 45.0% | $0.16 | |
| Hermes MiMo (prompted) | 64.9% | $0.18 | |
| Codex + GPT-5.4 | 74.2% | $0.21 | |
| Forge + Gemini 3.1 Pro | 61.1% | - | |
| Forge + Sonnet 4.6 | 72.4% | - | |
| FL Supervisor (Opus) | 44.0% | $0.26 | |
| CRUSH (MiniMax M2.7) | 72.7% | $0.39 | |
| CRUSH (Kimi K2.5) | 66.3% | $0.47 | |
| CRUSH (MiniMax M2.5) | 61.7% | $0.47 | |
| **Qwen+Sonnet-verify (Neuralwatt+Sonnet)** | **83.3%** | **$0.51** | **best <$0.74** |
| CRUSH (GLM-4.7-Flash) | 55.9% | $0.54 | |
| Conclave v8 Bare (Sonnet) | 83.4% | $0.69 | |
| Conclave v7 Lite (Sonnet) | 80.3% | $0.71 | |
| Metacog Routed (Sonnet) | 84.8% | $0.73 | |
| CRUSH (GLM5) | 81.7% | $0.73 | |
| **Conclave v8 Outcomes (Sonnet)** | **87.7%** | **$0.74** | **best <$0.82** |
| Conclave v8 Contract (Sonnet) | 86.5% | $0.74 | |
| v11 Qwen-routed (Neuralwatt+Sonnet) | 86.3% | $0.74 | |
| Conclave v8 Contract (Sonnet) | 86.5% | $0.74 | |
| ExoMonad v2 | 80.9% | $0.75 | |
| Conclave v8 Bare (Sonnet) | 83.4% | $0.69 | |
| Conclave v8 Outcomes (Sonnet) | 87.7% | $0.74 | |
| Conclave v8 Eval (Sonnet) | 87.2% | $0.78 | |
| Conclave v8 No-Review (Sonnet) | 87.1% | $0.78 | |
| Conclave v8 No-TDD (Sonnet) | 87.6% | $0.80 | |
| Conclave v8 High Effort (Sonnet) | 87.3% | $0.80 | |
| **Conclave v8 (Sonnet)** | **88.6%** | **$0.82** | **best <$1.23** |
| Claude Code + GLM-5.1-fast (Neuralwatt) | 76.3% | $0.83 | |
| Conclave v8 No-Review Ralph (Sonnet) | 87.2% | $0.83 | |
| Conclave v8 TDD-Hard (Sonnet) | 86.4% | $0.84 | |
| Conclave v8 No-Boil (Sonnet) | 87.7% | $0.89 | |
| Conclave v8 No-Contract (Sonnet) | 87.0% | $0.89 | |
| ExoMonad v1 | 74.8% | $0.84 | |
| Sonnet gstack | 87.3% | $0.92 | |
| Sonnet Plans | 87.3% | $0.92 | |
| Conclave v8 Ralph (Sonnet) | 87.9% | $0.93 | |
| Verify (Opus) | 80.8% | $0.94 | |
| Claude Code NoGit | 85.0% | $1.00 | |
| Claude Code Worktree | 80.0% | $1.00 | |
| Gas Station | 84.6% | $1.08 | |
| Tango and Cash | 84.8% | $1.10 | |
| Claude Code Branch | 85.8% | $1.11 | |
| Conclave v6 (Sonnet) | 86.5% | $1.11 | |
| GSD | 82.9% | $1.13 | |
| Sonnet Plans+gstack | 86.7% | $1.17 | |
| Claude Code (Opus) | 84.0% | $1.18 | |
| **Conclave v10 Routed** | **90.4%** | **$1.23** | **best overall** |
| Self-Review (Opus) | 81.9% | $1.23 | |
| Plans (Opus) | 87.6% | $1.26 | |
| gstack | 86.3% | $1.32 | |
| Ralph Fresh (Opus) | 87.2% | $1.34 | |
| Conclave v7 Lite (Opus) | 85.6% | $1.36 | |
| Conclave Design | 84.0% | $1.45 | |
| Conclave v8 (Opus) | 88.7% | $1.45 | |
| Stacked | 86.8% | $1.58 | |
| Conclave v9 Review Slim (Sonnet) | 87.5% | $1.72 | |
| Conclave v8 Contract (Opus) | 87.5% | $1.60 | |
| Conclave v8 TDD-Hard (Opus) | 83.4% | $1.62 | |
| BMAD-METHOD | 87.3% | $1.74 | |
| Conclave Review | 87.8% | $1.86 | |
| Conclave v6 (Opus) | 85.8% | $2.10 | |
| CRUSH (Nemotron 120B prompted) | 63.7% | $2.16 | |
| CRUSH (GLM-5-Turbo) | 73.7% | $2.27 | |
| Gas Town | 83.0% | $2.38 | |
| CRUSH (Nemotron 120B) | 68.5% | $2.50 | |
| Conclave v7 Double Review (Sonnet) | 84.4% | $2.80 | |
| Agent Teams | 86.3% | $3.29 | |

## Throughput

Wall-clock output tokens per second, measured across all trials for each orchestrator. Includes tool calls, test execution, and lint runs -- so these numbers reflect the agent's experienced throughput, not pure generation speed on an empty prompt.

| Orchestrator | Model | Host | Mean tok/s | Max |
|---|---|---|---:|---:|
| Cerebras CLI Ralph | gpt-oss-120b | Cerebras Cloud | **185** | 185 |
| CRUSH Nemotron 120B | Nemotron 3 Super 120B | Synthetic API | **109** | 186 |
| CRUSH Qwen3-Coder 30B | Qwen3-Coder 30B AWQ | local vLLM (RTX 5090) | **94** | 141 |
| CRUSH Qwen 3.5 32B | Qwen 3.5 32B | local vLLM (RTX 5090) | 81 | 130 |
| Aider Qwen3-Coder | Qwen3-Coder 30B Q5_K_M | local llama.cpp | 67 | 148 |
| CRUSH GLM-4.7-fast | GLM-4.7-Flash | z.ai | 64 | 104 |
| Claude Code + Qwen3.6 (19-way parallel) | Qwen3.6-35B-A3B | Neuralwatt | 64 | 133 |
| Zen-lite + Qwen3.6 (19-way parallel) | Qwen3.6-35B-A3B | Neuralwatt | 42 | 64 |
| Dao + Qwen3.6 (19-way parallel) | Qwen3.6-35B-A3B | Neuralwatt | 35 | 69 |
| Conclave v8 (Sonnet) | Claude Sonnet 4.6 | Anthropic | 54 | 73 |
| CRUSH Devstral 24B | Devstral 24B | local vLLM | 53 | 70 |
| CRUSH MiniMax M2.5 | MiniMax M2.5 | OpenRouter | 50 | 77 |
| Conclave v8 (Opus) | Claude Opus 4.6 | Anthropic | 49 | 66 |
| CRUSH Qwen3-Coder Q4_K_S | Qwen3-Coder 30B Q4_K_S | local llama.cpp | 48 | 93 |
| Hermes MiMo-V2-Flash | MiMo-V2-Flash | OpenRouter | 47 | 89 |
| CRUSH Qwen3-Coder Q5_K_M | Qwen3-Coder 30B Q5_K_M | local llama.cpp | 42 | 94 |
| CRUSH Kimi K2.5 | Kimi K2.5 | proxy | 34 | 86 |
| Claude Code + GLM-5.1-fast | GLM-5.1-FP8 | Neuralwatt | 32 | 50 |
| Claude Code + GLM-5 | GLM-5 | z.ai | 24 | 35 |

Three findings worth naming:

**Local GPUs beat hosted frontier APIs on throughput.** Qwen3-Coder 30B AWQ on a single RTX 5090 averages 94 tok/s -- nearly twice Opus (49) and meaningfully ahead of Sonnet (54). The Anthropic models aren't slow; the bottleneck is shared-tenant queueing, not model speed. A dedicated GPU wins on latency even with a weaker model.

**Cerebras is in a class of its own.** gpt-oss-120b on Cerebras Cloud averages 185 wall-clock tok/s including ralph loop orchestration -- ~3.8x Opus, ~1.7x Nemotron. Cerebras's silicon is purpose-built for fast inference; the wall-clock number is dragged down by test execution and setup, but pure generation on Cerebras is documented at 3,000+ tok/s. Specialized hardware wins the raw speed race.

**Nemotron 120B via Synthetic is the fastest conventional-GPU hosted model.** 109 tok/s mean, 186 max. That's ~2x Sonnet, 2.2x Opus. Synthetic's infrastructure is tuned for throughput; the model itself isn't smaller than the competition. Speed and quality are independent axes.

**"Fast" in a model name is not a guarantee.** GLM-5.1-**fast** on Neuralwatt runs at 32 tok/s -- slower than every local variant we tested and half the speed of GLM-4.7-**Flash** (64 tok/s). Branding doesn't predict throughput. Benchmark your inference.

**Parallel scaling beats per-trial speed at cluster level.** Neuralwatt's Qwen3.6-35B-A3B endpoint runs at 64 tok/s per trial (vanilla Claude Code) -- unremarkable in isolation, behind dedicated GPUs (94 tok/s on RTX 5090) and Cerebras (185). But Neuralwatt sustained 19 concurrent sessions with zero crashes and minimal per-trial slowdown, for a cluster aggregate of ~1,200 tok/s. Actual billing came in at $0.00208/request (342 requests / $0.71), so a full 19-task suite at ~50 turns each costs ~$0.10/task -- still cheaper than every hosted frontier model by an order of magnitude. When throughput-at-scale matters more than single-request latency, pay-per-watt infrastructure wins.

**Calm-framing prompts cost throughput.** Plain Claude Code + Qwen3.6 runs at 64 tok/s, but adding the zen-lite prompt drops it to 42 tok/s and Dao to 35 tok/s -- a 34-45% throughput hit. The model spends more tokens reasoning before acting (that's the point of the prompt). Wall-clock runtime goes up proportionally, but quality goes up further: zen-lite lifts Qwen3.6 from 70.3% to 76.1% and holds it. You're trading time and energy for correctness; on reasoning-heavy tasks that's a good trade.

## The Gas Station Story

[Gas Town](https://github.com/steveyegge/gastown) is a multi-agent pipeline: a Mayor decomposes the task, parallel Polecats implement pieces in git worktrees, and a Refinery merges their work. We asked Claude Code to build the adapter.

It delivered a fraud. A single `claude -p` call with Gas Town's context injected, wearing the scaffolding like a trench coat. It set up the town, created beads, initialized a polecat worktree — the whole ceremony — then ran one agent that did all the work. A single agent pretending to be a workforce.

I named the impostor "Gas Station" and kept it as a control.

Gas Station scored 88.5% standard. The fraud outperforms the real multi-agent pipeline on standard tasks. Gas Town scores higher on hard tasks (86.3% vs 80.6%) where parallel decomposition helps, but at 2x the cost ($2.38 vs $1.08).

Complexity must earn its keep.

## Benchmark Suite

Nineteen tasks across eight categories. All use TypeScript/Node.js with Vitest. Orchestrators cannot cheat by modifying tests. Validation runs `npm run build && npm run lint && npm test`.

**Standard Suite (T1-T11)**

| # | Task | Category | Timeout | Tests |
|---|------|----------|---------|-------|
| 1 | CLI Time Tracker | greenfield/simple | 15m | 25 |
| 2 | Collab Server | greenfield/complex | 45m | 45 |
| 3 | FTS Search | features/medium | 30m | 35 |
| 4 | Phantom Invoice Bug | bugfix/medium | 20m | 41 |
| 5 | Task Queue Marathon | marathon | 60m | 90 |
| 6 | Monorepo Disaster | recovery | 30m | 49 |
| 7 | Plugin Marketplace | greenfield/complex | 45m | 55 |
| 8 | Analytics Dashboard | greenfield/complex | 45m | 50 |
| 9 | SSG Toolkit | features/complex | 45m | 75 |
| 10 | E-Commerce Backend | greenfield/complex | 45m | 70 |
| 11 | Debug Nightmare | bugfix/hard | 30m | 49 |

**Hard Suite (T12-T19)** — designed to differentiate where the standard suite could not. Naive approaches fail at scale; agents must discover efficient algorithms.

| # | Task | Category | Key Challenge | Timeout | Hidden Tests |
|---|------|----------|---------------|---------|------|
| 12 | Constraint Scheduler | algorithmic/hard | Backtracking + constraint propagation | 45m | 38 |
| 13 | Structural Merge | algorithmic/hard | 3-way tree merge with conflict detection | 45m | 22 |
| 14 | Financial Ledger | correctness/hard | Double-entry accounting invariants | 30m | 35 |
| 15 | Permission Maze | ambiguity/hard | Deliberately vague spec; agents must infer rules | 45m | 52 |
| 16 | Reactive Spreadsheet | algorithmic/hard | Topological sort + cycle detection + propagation | 45m | 77 |
| 17 | Circuit Debugger | reasoning/hard | Structural analysis beats simulation at scale | 45m | 20 |
| 18 | Beam Splitter | reasoning/hard | Counter propagation vs path enumeration (2^K paths) | 45m | 23 |
| 19 | Factory Reset | reasoning/hard | GF(2) linear algebra (toggle = XOR = Gaussian elimination) | 45m | 20 |

### Scoring

Two scoring paths based on task type:

- **Standard tasks**: `composite = tests × 0.7 + static_analysis × 0.3`
- **Greenfield tasks**: `composite = hidden_tests × 0.385 + (agent_tests × coverage) × 0.308 + build_lint × 0.154 + code_metrics × 0.154`

## Contenders

| Orchestrator | Architecture | Key Differentiator |
|---|---|---|
| [Conclave](https://github.com/signalnine/conclave) v10 Routed | Haiku classifier -> Opus/Sonnet + no-review v8 | Highest overall; Haiku routes 17/19 tasks to Opus |
| Metacog Routed (Sonnet) | Haiku classifier -> per-category stratagem + Sonnet | Per-task stratagem routing; new Pareto at $0.73 |
| [Conclave](https://github.com/signalnine/conclave) v8 (Opus) | 6-step methodology prompt + Opus 4.6 | TDD + contracts + self-review |
| [Conclave](https://github.com/signalnine/conclave) v8 (Sonnet) | 6-step methodology prompt + Sonnet 4.6 | Same methodology at half the cost; ties Opus |
| [Conclave](https://github.com/signalnine/conclave) Review | Claude Code + consensus review | Code review only -- no skills, no planning |
| Plans (Opus) | Claude Code + writing-plans skill | Plan-before-code on Opus |
| [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) | Third-party structured workflow | Adversarial self-review with role-based phases |
| Sonnet [gstack](https://github.com/garrytan/gstack) | Claude Code Sonnet + gstack CLAUDE.md | "Boil the Lake" completeness principle |
| Sonnet Plans | Claude Code Sonnet + writing-plans skill | Plan-before-code on Sonnet |
| Ralph Fresh (Opus) | Claude Code + fresh-context loop | Multi-iteration fresh context on same workspace |
| Stacked | Metacog + review + worktree | Three top genes combined |
| Sonnet Plans+gstack | Claude Code Sonnet + plans + gstack | Two high-ROI genes stacked |
| [Conclave](https://github.com/signalnine/conclave) v9 Review Slim (Sonnet) | Two-pass: v8 then hostile review+fix | Second pass costs 2x, loses 1.1pp |
| [Conclave](https://github.com/signalnine/conclave) v8 No-Review (Sonnet) | v8 minus self-review | Ablation: 87.1% at $0.78; review adds 1.5pp |
| [Conclave](https://github.com/signalnine/conclave) v8 No-Boil (Sonnet) | v8 minus "Boil the Lake" | Ablation: 87.7% at $0.89; completeness adds 0.9pp |
| [Conclave](https://github.com/signalnine/conclave) v8 No-Contract (Sonnet) | v8 minus CONTRACT.md | Ablation: 87.0% at $0.89; contract adds 1.6pp |
| [Conclave](https://github.com/signalnine/conclave) v8 No-TDD (Sonnet) | v8 minus test-first development | Ablation: 87.6% at $0.80; TDD adds 1.0pp |
| [Conclave](https://github.com/signalnine/conclave) v8 Bare (Sonnet) | v8 with all methodology removed | Baseline: 83.4% at $0.69; methodology adds 5.2pp total |
| [Conclave](https://github.com/signalnine/conclave) v8 Outcomes (Sonnet) | v8 + deterministic iteration loop | Harness-enforced retry with test/build feedback |
| [Conclave](https://github.com/signalnine/conclave) v8 Eval (Sonnet) | v8 + two-pass evaluator diagnosis | External diagnostic agent between passes |
| [Conclave](https://github.com/signalnine/conclave) v8 Contract (Sonnet/Opus) | v8 contract-focused, weaker TDD | Tests contract gene in isolation |
| [Conclave](https://github.com/signalnine/conclave) v8 TDD-Hard (Sonnet/Opus) | v8 TDD-focused, no contract | Tests TDD gene in isolation |
| [Conclave](https://github.com/signalnine/conclave) v7 Lite (Opus) | Conclave plugin + Opus 4.6 | v7 adaptive routing -- double-review on state-heavy tasks |
| [Conclave](https://github.com/signalnine/conclave) v7 Double Review (Sonnet) | Conclave plugin + Sonnet 4.6 | Conditional second review on state-heavy tasks |
| [Conclave](https://github.com/signalnine/conclave) v7 Lite (Sonnet) | Conclave plugin + Sonnet 4.6 | Same v7 routing on Sonnet; cheapest Conclave at $0.71 |
| [Conclave](https://github.com/signalnine/conclave) v6 (Sonnet) | Conclave plugin + Sonnet 4.6 | Task classifier + completion gate; consensus opt-in |
| Agent Teams | Claude Code interactive + teams | Experimental parallel teammates |
| [gstack](https://github.com/garrytan/gstack) | Claude Code Opus + gstack CLAUDE.md | "Boil the Lake" on Opus |
| Claude Code Branch | Claude Code + `git checkout -b main` | Branch from detached HEAD before agent runs |
| [Conclave](https://github.com/signalnine/conclave) v6 (Opus) | Conclave plugin + Opus 4.6 | Same plugin as Sonnet v6, higher model cost |
| Claude Code NoGit | Claude Code + .git removed | No git directory in workspace |
| Tango and Cash | Opus + Gemini CLI | Claude plans, Gemini implements |
| Gas Station | Single-agent + context injection | Gas Town ceremony without multi-agent execution |
| [Conclave](https://github.com/signalnine/conclave) Design | Claude Code + consensus design | Pre-implementation architecture review |
| Claude Code (Opus) | Vanilla single agent | Rich tool use, subagent delegation |
| [Gas Town](https://github.com/steveyegge/gastown) | Multi-agent pipeline | Mayor -> parallel Polecats -> Refinery |
| [GSD](https://github.com/gsd-build/get-shit-done) | Third-party wave-based execution | Parallel wave execution with dependency tracking |
| Self-Review (Opus) | Claude Code + system prompt only | No plugins — just "verify, commit, review diff, fix" |
| [CRUSH](https://github.com/nicepkg/crush) (GLM5) | CRUSH CLI + GLM-5 | Simple read-code-test-fix loop |
| Claude Code + GLM-5.1-fast (Neuralwatt) | Claude Code protocol + GLM-5.1-FP8 | Neuralwatt's native Anthropic-compatible endpoint |
| Gemini CLI | Google's agentic CLI | Gemini 2.5 Pro via Google One OAuth |
| [ExoMonad v2](https://github.com/tidepool-heavy-industries/exomonad) | Haskell WASM + Rust runtime | Claude decomposes, Gemini implements via MCP; guided TL behavior |
| Verify (Opus) | Claude Code + verification skill | "No completion claims without fresh evidence" |
| Claude Code Worktree | Claude Code + git worktree | Worktree isolation variant |
| Debug (Opus) | Claude Code + debugging skill | Four-phase systematic debugging methodology |
| [Amplifier](https://github.com/microsoft/amplifier) (Gemini 2.5 Flash) | Microsoft Amplifier + Gemini Flash | Micro-kernel platform, cheapest usable orchestrator |
| [ExoMonad v1](https://github.com/tidepool-heavy-industries/exomonad) | Haskell WASM + Rust runtime | Claude decomposes, Gemini implements via MCP |
| Cerebras CLI Ralph | OpenCode fork + gpt-oss-120b | Full agentic tool use via Cerebras inference |
| CRUSH (GLM-5-Turbo) | CRUSH CLI + GLM-5-Turbo | Agent-optimized GLM-5 variant, 3x cost of GLM-5 |
| CRUSH (MiniMax M2.7) | CRUSH CLI + MiniMax M2.7 (via OpenRouter) | +11pp over M2.5 at lower cost ($0.39 vs $0.47) |
| CRUSH (Nemotron 120B) | CRUSH CLI + Nemotron 3 Super 120B | 120B MoE via Synthetic API |
| CRUSH (Kimi K2.5) | CRUSH CLI + Kimi K2.5 | Open-weight model via proxy |
| [Hermes](https://github.com/anthropics/hermes) MiMo | Hermes agent + MiMo-V2-Flash | Cheapest full-suite model at $0.16/task |
| CRUSH (MiniMax M2.5) | CRUSH CLI + MiniMax M2.5 | Open-weight model via proxy |
| CRUSH Meditation (Qwen3-Coder 30B Q4_K_S) | CRUSH CLI + meditation CRUSH.md (local llama.cpp) | Zen-adapted prompt, new best local at 59.8% |
| CRUSH (Qwen3-Coder 30B Q4_K_S) | CRUSH CLI + Qwen3-Coder 30B (local llama.cpp) | Baseline Q4_K_S quant for meditation A/B test |
| CRUSH (Qwen3-Coder 30B) | CRUSH CLI + Qwen3-Coder 30B AWQ (local vLLM) | Local RTX 5090 inference, $0/task |
| Aider (Qwen3-Coder 30B Q5_K_M) | Aider + Qwen3-Coder 30B (local llama.cpp) | Single-pass diff edits on local GPU |
| CRUSH (GLM-4.7-Flash) | CRUSH CLI + GLM-4.7-Flash | Smaller GLM variant |
| CRUSH (Qwen3-Coder 30B Q5_K_M) | CRUSH CLI + Qwen3-Coder 30B (local llama.cpp) | Higher-quality quant on llama.cpp |
| CRUSH (Qwen 3.5 32B) | CRUSH CLI + Qwen 3.5 32B (local vLLM) | CRUSH system prompt nearly tripled score from ~20% |
| CRUSH (Devstral 24B) | CRUSH CLI + Devstral 24B (local vLLM) | Local inference with Mistral tool calling |
| FL Supervisor Pro | Gemini 2.5 Pro supervisor | Multi-agent supervisor pattern |
| FL Supervisor (Opus) | Opus 4.6 supervisor | Same supervisor pattern, different model |

## How It Works

```
thunderdome run
  |
  ├─ Clone task repo at pinned tag
  ├─ Launch orchestrator in Docker container
  │    ├─ Mount adapter script, task description, workspace
  │    ├─ Orchestrator reads TASK.md, writes code to /workspace
  │    └─ Container exits on completion, timeout, or crash
  ├─ Capture git diff of workspace changes
  ├─ Run validation pipeline
  │    ├─ Tests (npm test in validation image)
  │    ├─ Build + lint (npm run build && npm run lint)
  │    └─ Greenfield extras: hidden tests, coverage, code metrics
  └─ Write results (meta.json, diff.patch, scores)
```

Each orchestrator plugs in through a shell adapter script mounted at `/adapter.sh`. The adapter translates between Thunderdome's interface (env vars `TASK_DIR`, `TASK_DESCRIPTION`, `PROXY_URL`) and the orchestrator's native invocation, then writes `.thunderdome-metrics.json` with token usage and cost data.

## Usage

### Prerequisites

- Go 1.24+
- Docker

### Build and Run

```sh
go build -o thunderdome .

# Run all orchestrators against all tasks
./thunderdome run

# Filter to one orchestrator or task
./thunderdome run --orchestrator conclave-review-opus
./thunderdome run --task T5

# Parallel containers, multiple trials
./thunderdome run --parallel 4 --trials 3

# Generate reports
./thunderdome report                     # defaults to results/latest
./thunderdome report --format markdown   # table, markdown, or json
```

## Project Structure

```
.
├── main.go                     # Entry point
├── cmd/                        # CLI commands (run, list, report)
├── internal/
│   ├── config/                 # YAML config parsing
│   ├── docker/                 # Container lifecycle
│   ├── runner/                 # Trial execution, validation, worker pool
│   ├── validation/             # Tests, lint, hidden tests, coverage, code metrics
│   ├── result/                 # Trial metadata types and storage
│   └── report/                 # Table/Markdown/JSON output
├── adapters/                   # Shell adapter scripts per orchestrator
├── benchmarks/                 # 19 task repos (each with v1/v1-solution tags)
├── docker/                     # Dockerfiles for orchestrator images
├── thunderdome.yaml            # Configuration
└── project.md                  # Full specification
```
