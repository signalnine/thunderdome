#!/usr/bin/env python3
"""Offline router-model comparison.

Reads ground-truth labels from ground_truth.json, sends the production routing
prompt to each candidate router via its native API, parses TRIVIAL/EASY/HARD,
and scores agreement.

Cost: ~$0.05 per candidate across 19 tasks. Most are sub-cent.

Usage:
    OPENROUTER_API_KEY=... DEEPSEEK_API_KEY=... python3 test_routers.py
    python3 test_routers.py --routers haiku,deepseek-flash,gemini-flash
    python3 test_routers.py --trials 3   # run each task N times to measure consistency
"""

from __future__ import annotations
import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
BENCH_DIR = ROOT / "benchmarks"
GT_PATH = Path(__file__).parent / "ground_truth.json"

ROUTING_PROMPT = """You are routing a coding task to one of three AI model tiers. Pick the cheapest tier that can reliably complete the task.

TIERS:
- TRIVIAL: Cheap fast model (DeepSeek). Handles concrete CRUD, formatting, basic feature additions with clear specs, simple bugfixes with obvious repro.
- EASY: Mid-tier model (Sonnet). Handles real state and multiple files, well-specified features with relationships, debugging where the issue requires investigation but follows standard patterns.
- HARD: Top-tier model (Opus). Handles algorithmic search under constraints (find-min/find-optimal), structural reasoning from behavior (reverse-engineer circuits/protocols), and tasks requiring careful invariant-preserving logic.

CALIBRATION EXAMPLES:

Task: "Build a CLI time tracker with start/stop/list commands, storing entries in a JSON file."
Tier: TRIVIAL
Reason: Concrete CRUD, well-defined data model, no algorithmic search.

Task: "Add a full-text search endpoint with stemming, ranking by BM25, and case-insensitive prefix matching."
Tier: TRIVIAL
Reason: Search library work with documented patterns; spec is unambiguous.

Task: "Build a plugin marketplace API with installations, dependency resolution by semver, and offline cache."
Tier: EASY
Reason: Multiple components and real state, but follows established patterns; semver resolution is standard.

Task: "Build a reactive spreadsheet where cell formula changes propagate through dependencies, detect cycles, and recompute only dirty cells."
Tier: EASY
Reason: Dependency graph + dirty propagation; standard reactive pattern.

Task: "Given observed circuit behavior with two swapped wires, identify which wires were swapped and produce the corrected wiring."
Tier: HARD
Reason: Structural reverse-engineering from behavior — requires careful reasoning about gate semantics.

Task: "Find the minimum set of button presses that toggles all N lights to ON, given each button toggles a fixed subset of lights."
Tier: HARD
Reason: Algorithmic search under constraints (set cover / XOR over GF(2)).

Task: "Given a corrupted factory state with missing config and partial production logs, rebuild the configuration that explains all observed log entries."
Tier: HARD
Reason: Stateful reconstruction from incomplete evidence; requires invariant reasoning.

INSTRUCTION: Read the task below. Respond with one word only: TRIVIAL, EASY, or HARD. No explanation.

=== TASK ===
"""

LABELS = ("TRIVIAL", "EASY", "HARD")


def parse_label(text: str) -> str:
    """Extract TRIVIAL/EASY/HARD from response. Default HARD on parse failure
    to match production behavior."""
    if not text:
        return "PARSE_FAIL"
    up = text.upper()
    # Order: HARD first to avoid matching it inside other words; then TRIVIAL; then EASY.
    if "HARD" in up:
        return "HARD"
    if "TRIVIAL" in up:
        return "TRIVIAL"
    if "EASY" in up:
        return "EASY"
    return "PARSE_FAIL"


BROWSER_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"


def post_json(url: str, headers: dict, body: dict, timeout: int = 60) -> dict:
    data = json.dumps(body).encode()
    # Add a browser UA by default (some providers like Neuralwatt require it
    # to clear Cloudflare). Caller can override.
    headers = {"User-Agent": BROWSER_UA, **headers}
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


# ---------- Provider clients ----------

def call_anthropic(model: str, prompt: str) -> tuple[str, float]:
    """Anthropic Messages API. Returns (text, est_cost_usd)."""
    key = os.environ["ANTHROPIC_API_KEY"]
    body = {
        "model": model,
        "max_tokens": 64,
        "messages": [{"role": "user", "content": prompt}],
    }
    r = post_json(
        "https://api.anthropic.com/v1/messages",
        {"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"},
        body,
    )
    text = r["content"][0]["text"] if r.get("content") else ""
    usage = r.get("usage", {})
    in_tok = usage.get("input_tokens", 0)
    out_tok = usage.get("output_tokens", 0)
    # Haiku 4.5 pricing: $1/MTok in, $5/MTok out (approximate)
    cost = in_tok * 1e-6 + out_tok * 5e-6
    return text, cost


def call_openai_compatible(url: str, key: str, model: str, prompt: str,
                            in_price: float, out_price: float,
                            max_tokens_key: str = "max_tokens",
                            max_tokens_value: int = 512,
                            include_temperature: bool = True) -> tuple[str, float]:
    """OpenAI-shape chat completions. in_price/out_price in $/MTok."""
    body = {
        "model": model,
        max_tokens_key: max_tokens_value,
        "messages": [{"role": "user", "content": prompt}],
    }
    if include_temperature:
        body["temperature"] = 0
    r = post_json(
        url,
        {"authorization": f"Bearer {key}", "content-type": "application/json"},
        body,
    )
    text = r["choices"][0]["message"].get("content", "") or ""
    usage = r.get("usage", {})
    in_tok = usage.get("prompt_tokens", 0)
    out_tok = usage.get("completion_tokens", 0)
    cost = in_tok * in_price * 1e-6 + out_tok * out_price * 1e-6
    return text, cost


def call_deepseek_flash(prompt: str) -> tuple[str, float]:
    return call_openai_compatible(
        "https://api.deepseek.com/v1/chat/completions",
        os.environ["DEEPSEEK_API_KEY"],
        "deepseek-chat",  # v4-flash on DeepSeek native is exposed as "deepseek-chat"
        prompt, 0.27, 1.10,
    )


def call_gemini(prompt: str, model: str, in_price: float, out_price: float) -> tuple[str, float]:
    """Gemini via Google's native API (not OpenAI-compatible by default)."""
    key = os.environ["GEMINI_API_KEY"]
    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"maxOutputTokens": 1024, "temperature": 0, "thinkingConfig": {"thinkingBudget": 0}},
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    r = post_json(url, {"content-type": "application/json"}, body)
    try:
        text = r["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError):
        text = ""
    usage = r.get("usageMetadata", {})
    in_tok = usage.get("promptTokenCount", 0)
    out_tok = usage.get("candidatesTokenCount", 0)
    cost = in_tok * in_price * 1e-6 + out_tok * out_price * 1e-6
    return text, cost


def call_neuralwatt(prompt: str, model: str) -> tuple[str, float]:
    """Neuralwatt: OpenAI-shape, energy-billed (treat cost as ~$0)."""
    return call_openai_compatible(
        "https://api.neuralwatt.com/v1/chat/completions",
        os.environ["NEURALWATT_API_KEY"],
        model, prompt, 0.0, 0.0,
    )


def call_openrouter(prompt: str, model: str, in_price: float, out_price: float) -> tuple[str, float]:
    return call_openai_compatible(
        "https://openrouter.ai/api/v1/chat/completions",
        os.environ["OPENROUTER_API_KEY"],
        model, prompt, in_price, out_price,
    )


def call_openai(prompt: str, model: str, in_price: float, out_price: float) -> tuple[str, float]:
    return call_openai_compatible(
        "https://api.openai.com/v1/chat/completions",
        os.environ["OPENAI_API_KEY"],
        model, prompt, in_price, out_price,
    )


def call_groq(prompt: str, model: str) -> tuple[str, float]:
    # Groq pricing varies by model; reporting $0 if unknown.
    return call_openai_compatible(
        "https://api.groq.com/openai/v1/chat/completions",
        os.environ.get("GROQ_API_KEY", ""),
        model, prompt, 0.0, 0.0,
    )


def call_cerebras(prompt: str, model: str) -> tuple[str, float]:
    return call_openai_compatible(
        "https://api.cerebras.ai/v1/chat/completions",
        os.environ["CEREBRAS_API_KEY"],
        model, prompt, 0.10, 0.10,
    )


def call_mistral(prompt: str, model: str, in_price: float, out_price: float) -> tuple[str, float]:
    return call_openai_compatible(
        "https://api.mistral.ai/v1/chat/completions",
        os.environ["MISTRAL_API_KEY"],
        model, prompt, in_price, out_price,
    )


def call_zhipu(prompt: str, model: str) -> tuple[str, float]:
    """Zhipu GLM. Disable thinking to keep classification fast and cheap."""
    body = {
        "model": model,
        "max_tokens": 16,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "thinking": {"type": "disabled"},
    }
    r = post_json(
        "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        {"authorization": f"Bearer {os.environ['ZHIPU_API_KEY']}", "content-type": "application/json"},
        body,
    )
    text = r["choices"][0]["message"].get("content", "") or ""
    usage = r.get("usage", {})
    in_tok = usage.get("prompt_tokens", 0)
    out_tok = usage.get("completion_tokens", 0)
    cost = in_tok * 0.0 + out_tok * 0.0  # GLM-4.7-flash on Zhipu is effectively free for low-volume
    return text, cost


# ---------- Candidate routers ----------

@dataclass
class Router:
    name: str
    call: Callable[[str], tuple[str, float]]  # prompt -> (text, cost)
    notes: str = ""


def _openai_reasoning(prompt: str, model: str, in_price: float, out_price: float):
    """GPT-5.x reasoning models require max_completion_tokens and no temperature."""
    return call_openai_compatible(
        "https://api.openai.com/v1/chat/completions",
        os.environ["OPENAI_API_KEY"],
        model, prompt, in_price, out_price,
        max_tokens_key="max_completion_tokens",
        max_tokens_value=64,
        include_temperature=False,
    )


ROUTERS: dict[str, Router] = {
    # Baseline -- current production router
    "haiku-4-5": Router(
        "haiku-4-5",
        lambda p: call_anthropic("claude-haiku-4-5", p),
        "current production router",
    ),
    # Cheap candidates
    "deepseek-chat": Router(
        "deepseek-chat",
        lambda p: call_deepseek_flash(p),
        "DeepSeek native chat (v4 Pro/Flash)",
    ),
    "gemini-3-flash": Router(
        "gemini-3-flash",
        lambda p: call_gemini(p, "gemini-3-flash-preview", 0.30, 2.50),
        "Google native API",
    ),
    "gemini-2.5-flash-lite": Router(
        "gemini-2.5-flash-lite",
        lambda p: call_gemini(p, "gemini-2.5-flash-lite", 0.075, 0.30),
        "Google cheap tier",
    ),
    "qwen3.6-neuralwatt": Router(
        "qwen3.6-neuralwatt",
        lambda p: call_neuralwatt(p, "Qwen/Qwen3.6-35B-A3B"),
        "Neuralwatt energy-billed",
    ),
    "glm-5.1-fast-neuralwatt": Router(
        "glm-5.1-fast-neuralwatt",
        lambda p: call_neuralwatt(p, "glm-5.1-fast"),
        "Neuralwatt energy-billed",
    ),
    "gpt-5.4-mini": Router(
        "gpt-5.4-mini",
        lambda p: _openai_reasoning(p, "gpt-5.4-mini", 0.15, 0.60),
        "OpenAI cheap reasoning",
    ),
    "gpt-5.4-nano": Router(
        "gpt-5.4-nano",
        lambda p: _openai_reasoning(p, "gpt-5.4-nano", 0.05, 0.20),
        "OpenAI cheapest reasoning",
    ),
    "mistral-small": Router(
        "mistral-small",
        lambda p: call_mistral(p, "mistral-small-latest", 0.20, 0.60),
        "Mistral cheap tier",
    ),
    "glm-4.7-flash-zhipu": Router(
        "glm-4.7-flash-zhipu",
        lambda p: call_zhipu(p, "glm-4.7-flash"),
        "Zhipu direct API",
    ),
    # Sanity check: also test the heavyweight to see if MORE capability helps
    "sonnet-4-6": Router(
        "sonnet-4-6",
        lambda p: call_anthropic("claude-sonnet-4-6", p),
        "upper bound on capability (expensive)",
    ),
}


# ---------- Test runner ----------

def load_tasks() -> list[dict]:
    """Returns list of {task_id, bench, label, prompt}."""
    gt = json.loads(GT_PATH.read_text())["labels"]
    tasks = []
    for tid in sorted(gt.keys(), key=lambda x: int(x[1:])):
        info = gt[tid]
        task_md = BENCH_DIR / info["bench"] / "TASK.md"
        prompt = task_md.read_text() if task_md.exists() else ""
        tasks.append({
            "task_id": tid,
            "bench": info["bench"],
            "label": info["label"],
            "prompt": prompt,
        })
    return tasks


def run_router(router: Router, tasks: list[dict], trials: int) -> list[dict]:
    out = []
    for t in tasks:
        full_prompt = ROUTING_PROMPT + t["prompt"]
        for trial in range(trials):
            row = {
                "router": router.name,
                "task_id": t["task_id"],
                "trial": trial,
                "ground_truth": t["label"],
                "raw": "",
                "predicted": "",
                "cost_usd": 0.0,
                "latency_s": 0.0,
                "error": "",
            }
            t0 = time.time()
            try:
                text, cost = router.call(full_prompt)
                row["raw"] = text.strip()[:200]
                row["predicted"] = parse_label(text)
                row["cost_usd"] = cost
            except urllib.error.HTTPError as e:
                row["error"] = f"HTTP {e.code}: {e.read()[:200].decode(errors='replace')}"
                row["predicted"] = "ERROR"
            except Exception as e:
                row["error"] = f"{type(e).__name__}: {e}"[:200]
                row["predicted"] = "ERROR"
            row["latency_s"] = round(time.time() - t0, 2)
            out.append(row)
            print(f"  {t['task_id']:>3} trial {trial}: GT={t['label']:<7} pred={row['predicted']:<10} "
                  f"${row['cost_usd']:.5f}  {row['latency_s']}s  raw={row['raw'][:50]!r}",
                  file=sys.stderr, flush=True)
    return out


def summarize(rows: list[dict]) -> dict:
    by_router: dict[str, list[dict]] = {}
    for r in rows:
        by_router.setdefault(r["router"], []).append(r)
    summary = {}
    for router, rs in by_router.items():
        total = len(rs)
        errors = sum(1 for r in rs if r["predicted"] == "ERROR")
        parse_fail = sum(1 for r in rs if r["predicted"] == "PARSE_FAIL")
        exact = sum(1 for r in rs if r["predicted"] == r["ground_truth"])
        # Acceptable: trip-wire matches (predicting same or HIGHER tier than GT
        # costs money but doesn't lose accuracy)
        TIER_RANK = {"TRIVIAL": 0, "EASY": 1, "HARD": 2}
        acceptable = sum(
            1 for r in rs
            if r["predicted"] in TIER_RANK and r["ground_truth"] in TIER_RANK
            and TIER_RANK[r["predicted"]] >= TIER_RANK[r["ground_truth"]]
        )
        # Under-routes: predicting LOWER tier than GT (real harm: weak model on hard task)
        under = sum(
            1 for r in rs
            if r["predicted"] in TIER_RANK and r["ground_truth"] in TIER_RANK
            and TIER_RANK[r["predicted"]] < TIER_RANK[r["ground_truth"]]
        )
        cost_total = sum(r["cost_usd"] for r in rs)
        lat_avg = sum(r["latency_s"] for r in rs) / max(total, 1)
        summary[router] = {
            "trials": total,
            "exact_match": exact,
            "exact_pct": round(100 * exact / total, 1) if total else 0,
            "acceptable_or_over": acceptable,
            "acceptable_pct": round(100 * acceptable / total, 1) if total else 0,
            "under_routes": under,
            "errors": errors,
            "parse_fail": parse_fail,
            "cost_total_usd": round(cost_total, 5),
            "cost_per_call_usd": round(cost_total / total, 5) if total else 0,
            "latency_avg_s": round(lat_avg, 2),
        }
    return summary


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--routers", default="", help="comma-separated list (default: all)")
    ap.add_argument("--trials", type=int, default=1, help="trials per task")
    ap.add_argument("--out", default=str(Path(__file__).parent / "results.json"))
    args = ap.parse_args()

    selected = list(ROUTERS.keys()) if not args.routers else [r.strip() for r in args.routers.split(",")]
    unknown = [r for r in selected if r not in ROUTERS]
    if unknown:
        print(f"unknown routers: {unknown}", file=sys.stderr)
        print(f"available: {sorted(ROUTERS.keys())}", file=sys.stderr)
        sys.exit(2)

    tasks = load_tasks()
    print(f"loaded {len(tasks)} tasks", file=sys.stderr)

    all_rows = []
    for name in selected:
        print(f"\n=== {name} ({ROUTERS[name].notes}) ===", file=sys.stderr)
        rows = run_router(ROUTERS[name], tasks, args.trials)
        all_rows.extend(rows)

    summary = summarize(all_rows)
    out = {"summary": summary, "rows": all_rows}
    Path(args.out).write_text(json.dumps(out, indent=2))
    print(f"\nwrote {args.out}", file=sys.stderr)

    # Print summary table
    print()
    print(f"{'router':<22} {'exact%':>7} {'accept%':>8} {'under':>6} {'err':>4} {'parse':>6} {'$/call':>10} {'lat':>6}")
    print("-" * 80)
    for name in selected:
        s = summary.get(name, {})
        if not s:
            continue
        print(f"{name:<22} {s['exact_pct']:>7} {s['acceptable_pct']:>8} {s['under_routes']:>6} "
              f"{s['errors']:>4} {s['parse_fail']:>6} {s['cost_per_call_usd']:>10.5f} {s['latency_avg_s']:>6}")


if __name__ == "__main__":
    main()
