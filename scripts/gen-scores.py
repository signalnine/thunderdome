#!/usr/bin/env python3
"""Generate leaderboard scores from meta.json files."""
import json, glob, sys, os
from collections import defaultdict

# Tasks
STANDARD_TASKS = {f"bench-{t}" for t in [
    "time-tracker", "collab-server", "fts-search", "phantom-invoice",
    "task-queue", "monorepo-disaster", "plugin-marketplace",
    "analytics-dashboard", "ssg-toolkit", "ecommerce-backend", "debug-nightmare"
]}
HARD_TASKS = {f"bench-{t}" for t in [
    "constraint-scheduler", "structural-merge", "financial-ledger",
    "permission-maze", "reactive-spreadsheet", "circuit-debugger",
    "beam-splitter", "factory-reset"
]}
TASK_IDS = {
    "bench-time-tracker": "T1", "bench-collab-server": "T2", "bench-fts-search": "T3",
    "bench-phantom-invoice": "T4", "bench-task-queue": "T5", "bench-monorepo-disaster": "T6",
    "bench-plugin-marketplace": "T7", "bench-analytics-dashboard": "T8",
    "bench-ssg-toolkit": "T9", "bench-ecommerce-backend": "T10", "bench-debug-nightmare": "T11",
    "bench-constraint-scheduler": "T12", "bench-structural-merge": "T13",
    "bench-financial-ledger": "T14", "bench-permission-maze": "T15",
    "bench-reactive-spreadsheet": "T16", "bench-circuit-debugger": "T17",
    "bench-beam-splitter": "T18", "bench-factory-reset": "T19",
}

_NO_COST_TRACKING = {"aider", "aider-gemini", "cerebras-cli", "cerebras-cli-ralph", "swe-agent"}

def is_crash(meta):
    orch = meta.get("orchestrator", "")
    cost = meta.get("total_cost_usd", None)
    dur = meta.get("duration_s", 0) or 0
    if orch in _NO_COST_TRACKING:
        return dur < 15
    return cost is None or cost == 0

# Load all meta.json
files = glob.glob("results/runs/*/trials/*/bench-*/trial-*/meta.json")
all_metas = []
for f in files:
    try:
        m = json.load(open(f))
        parts = f.split("/")
        m["_orch"] = parts[4]
        m["_task"] = parts[5]
        all_metas.append(m)
    except:
        pass

total = len(all_metas)
crashes = [m for m in all_metas if is_crash(m)]
good = [m for m in all_metas if not is_crash(m)]

print("=" * 120)
print("SUMMARY STATISTICS")
print("=" * 120)
print(f"Total meta.json files:  {total}")
print(f"Non-crash trials:       {len(good)}")
print(f"Crash trials filtered:  {len(crashes)}")

# Unique orchestrators/tasks
orchs = set(m["_orch"] for m in good)
tasks = set(m["_task"] for m in good)
print(f"Unique orchestrators:   {len(orchs)}")
print(f"Unique tasks:           {len(tasks)}")

# Crash breakdown
crash_by_orch = defaultdict(int)
for m in crashes:
    crash_by_orch[m["_orch"]] += 1
print(f"\nCrash trials by orchestrator:")
for o, c in sorted(crash_by_orch.items(), key=lambda x: -x[1]):
    print(f"  {o:45s} {c}")

# Per-orchestrator, per-task scores
scores = defaultdict(lambda: defaultdict(list))
costs = defaultdict(list)
for m in good:
    score = m.get("composite_score", 0) or 0
    cost = m.get("total_cost_usd", 0) or 0
    scores[m["_orch"]][m["_task"]].append(score)
    costs[m["_orch"]].append(cost)

# Summaries
def summarize(orch):
    task_scores = scores[orch]
    std_means = []
    hard_means = []
    std_count = 0
    hard_count = 0
    per_task = {}
    for task, vals in task_scores.items():
        mean = sum(vals) / len(vals)
        per_task[task] = (mean, len(vals))
        if task in STANDARD_TASKS:
            std_means.append(mean)
            std_count += len(vals)
        elif task in HARD_TASKS:
            hard_means.append(mean)
            hard_count += len(vals)
    std_mean = sum(std_means) / len(std_means) if std_means else None
    hard_mean = sum(hard_means) / len(hard_means) if hard_means else None
    if std_mean is not None and hard_mean is not None:
        overall = (std_mean + hard_mean) / 2
    else:
        overall = None
    cost_list = costs[orch]
    avg_cost = sum(cost_list) / len(cost_list) if cost_list else 0
    total_trials = sum(len(v) for v in task_scores.values())
    return {
        "standard_mean": std_mean, "hard_mean": hard_mean, "overall": overall,
        "avg_cost": avg_cost, "total_trials": total_trials,
        "std_trial_count": std_count, "hard_trial_count": hard_count,
        "per_task": per_task,
        "std_task_count": len(std_means), "hard_task_count": len(hard_means),
    }

summaries = {o: summarize(o) for o in orchs}

# Has both standard and hard
both = {k: v for k, v in summaries.items()
        if v["standard_mean"] is not None and v["hard_mean"] is not None}
std_only = {k: v for k, v in summaries.items()
            if v["standard_mean"] is not None and v["hard_mean"] is None}

n_both = len(both)
n_std = len(std_only)
print(f"  Both standard+hard:   {n_both}")
print(f"  Standard only:        {n_std}")
print(f"  Hard only:            {len(summaries) - n_both - n_std}")

# Main leaderboard (8+ std AND 8+ hard)
MIN_STD = 8
MIN_HARD = 8
eligible = {k: v for k, v in both.items()
            if v["std_trial_count"] >= MIN_STD and v["hard_trial_count"] >= MIN_HARD}

print(f"\n{'=' * 120}")
print("MAIN LEADERBOARD -- Orchestrators with both Standard (T1-T11) and Hard (T12-T19) scores")
print(f"{'=' * 120}")
ranked = sorted(eligible.items(), key=lambda x: -(x[1]["overall"] or 0))
print(f"{'Rank':>4}  {'Orchestrator':<45} {'Overall':>7}  {'Standard':>8}  {'Hard':>7}  {'Trials':>6}  {'$/task':>6}  {'Std#':>4} {'Hard#':>4}")
print("-" * 120)
for i, (o, s) in enumerate(ranked, 1):
    cost_str = f"${s['avg_cost']:.2f}" if s['avg_cost'] > 0 else "  -  "
    print(f"{i:>4}  {o:<45} {s['overall']*100:>6.1f}%  {s['standard_mean']*100:>7.1f}%  {s['hard_mean']*100:>6.1f}%  {s['total_trials']:>6}  {cost_str:>6}  {s['std_trial_count']:>4} {s['hard_trial_count']:>4}")

# Markdown
print(f"\n### Markdown format\n")
print("| Rank | Orchestrator | Overall | Standard | Hard | Trials | $/task |")
print("|------|-------------|---------|----------|------|--------|--------|")
for i, (o, s) in enumerate(ranked, 1):
    cost_str = f"${s['avg_cost']:.2f}" if s['avg_cost'] > 0 else "  -  "
    print(f"| {i} | {o} | {s['overall']*100:.1f}% | {s['standard_mean']*100:.1f}% | {s['hard_mean']*100:.1f}% | {s['total_trials']} | {cost_str} |")

# Hard task breakdown
print(f"\n{'=' * 120}")
print("HARD TASK BREAKDOWN (T12-T19) -- Per-task mean scores")
print(f"{'=' * 120}")
hard_orchs = {k: v for k, v in summaries.items() if v["hard_mean"] is not None}
hard_ranked = sorted(hard_orchs.items(), key=lambda x: -(x[1]["hard_mean"] or 0))
hard_task_order = sorted(HARD_TASKS, key=lambda t: TASK_IDS.get(t, t))
header = f"{'Orchestrator':<45} {'Hard':>7}"
for t in hard_task_order:
    header += f"  {TASK_IDS.get(t, t):>6}"
header += f"  {'#':>4}"
print(header)
print("-" * len(header))
for o, s in hard_ranked:
    line = f"{o:<45} {s['hard_mean']*100:>6.1f}%"
    n = 0
    for t in hard_task_order:
        if t in s["per_task"]:
            mean, cnt = s["per_task"][t]
            line += f"  {mean*100:>5.1f}%"
            n += cnt
        else:
            line += f"  {'  -  ':>6}"
    line += f"  {s['hard_trial_count']:>4}"
    print(line)

# Markdown
print(f"\n### Markdown format\n")
print("| Orchestrator | Hard | T12 | T13 | T14 | T15 | T16 | T17 | T18 | T19 | n |")
print("|------|------|------|------|------|------|------|------|------|------|------|")
for o, s in hard_ranked:
    line = f"| {o} | {s['hard_mean']*100:.1f}%"
    for t in hard_task_order:
        if t in s["per_task"]:
            mean, _ = s["per_task"][t]
            line += f" | {mean*100:.1f}%"
        else:
            line += " |   -  "
    line += f" | {s['hard_trial_count']} |"
    print(line)

# Standard task breakdown
print(f"\n{'=' * 120}")
print("STANDARD TASK BREAKDOWN (T1-T11) -- Per-task mean scores")
print(f"{'=' * 120}")
std_orchs = {k: v for k, v in summaries.items() if v["standard_mean"] is not None}
std_ranked = sorted(std_orchs.items(), key=lambda x: -(x[1]["standard_mean"] or 0))
std_task_order = sorted(STANDARD_TASKS, key=lambda t: TASK_IDS.get(t, t))
header = f"{'Orchestrator':<45} {'Std':>7}"
for t in std_task_order:
    header += f"  {TASK_IDS.get(t, t):>6}"
header += f"  {'#':>4}"
print(header)
print("-" * (len(header) + 10))
for o, s in std_ranked:
    line = f"{o:<45} {s['standard_mean']*100:>6.1f}%"
    for t in std_task_order:
        if t in s["per_task"]:
            mean, cnt = s["per_task"][t]
            line += f"  {mean*100:>5.1f}%"
        else:
            line += f"  {'  -  ':>6}"
    line += f"  {s['std_trial_count']:>4}"
    print(line)
