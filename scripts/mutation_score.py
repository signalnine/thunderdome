#!/usr/bin/env python3
"""
Mutation-testing primitive for thunderdome (deterministic test-QUALITY metric).

Inspired by FrontierCode's "reverse-classical" grading: a good test suite must
FAIL on broken code. We mutate the reference solution (known-good) to inject
realistic single-point bugs, keep only the mutants that are genuinely detectable
(the reference's own hidden tests fail on them), then score a candidate test
suite by the fraction of those valid mutants it KILLS (i.e., its tests fail).

mutation_score = killed_by_candidate / valid_mutants   in [0,1]

This is strictly stronger than coverage: coverage proves a line ran; a kill
proves the suite ASSERTS the line's behavior. Fully deterministic, no LLM judge.

Usage:
  mutation_score.py --repo benchmarks/bench-constraint-scheduler \
      --src src/scheduler.ts \
      --candidate <dir-with-*.test.ts>   # omit to just report the valid mutant set
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile

# Curated mutation operators: (name, regex, replacement). Each flips one
# realistic correctness decision. Applied to the reference source; only those
# that compile AND are caught by the hidden tests count as "valid mutants".
MUTATORS = [
    ("relational_le_to_lt",   r"<=", "<"),
    ("relational_ge_to_gt",   r">=", ">"),
    ("relational_lt_to_le",   r"(?<![<>=!])<(?![=])", "<="),
    ("relational_gt_to_ge",   r"(?<![<>=!])>(?![=])", ">="),
    ("logical_and_to_or",     r"&&", "||"),
    ("eq_to_neq",             r"===", "!=="),
    ("neq_to_eq",             r"!==", "==="),
    ("plus_gap_to_minus",     r"\+ gap", "- gap"),
    ("inc_to_dec",            r"\+ 1\b", "- 1"),
    ("dec_to_inc",            r"- 1\b", "+ 1"),
    ("return_true_to_false",  r"return true;", "return false;"),
    ("drop_throw",            r"throw new Error\(", "void (("),  # neutralize a throw (kept compilable-ish)
]

def run(cmd, cwd, timeout=120):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"

def tests_pass(workdir):
    """Return True if the validation suite passes (exit 0) in workdir."""
    rc, _ = run(["npx", "vitest", "run", "--config", "validation-vitest.config.ts"], workdir)
    return rc == 0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--src", required=True, help="reference source file, relative to repo (e.g. src/scheduler.ts)")
    ap.add_argument("--candidate", help="dir containing candidate *.test.ts (placed in validation-tests/); omit to only build the valid-mutant set")
    ap.add_argument("--max-per-op", type=int, default=2, help="cap mutants per operator to keep runtime bounded")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    base = tempfile.mkdtemp(prefix="mut-")
    # Materialize v1-validation (reference src + hidden tests + configs) as the harness.
    subprocess.run(f"git -C {repo} archive v1-validation | tar -x -C {base}", shell=True, check=True)
    subprocess.run(["npm", "install", "--ignore-scripts", "--no-audit", "--no-fund"], cwd=base,
                   capture_output=True)
    ref_src = os.path.join(base, args.src)
    original = open(ref_src).read()

    # 1) Sanity: reference passes its own hidden tests.
    assert tests_pass(base), "reference solution does not pass hidden tests — abort"

    # 2) Generate candidate mutants, keep only VALID ones (compile + caught by hidden tests).
    valid = []   # list of (mutant_id, mutated_source)
    for name, pat, repl in MUTATORS:
        hits = list(re.finditer(pat, original))
        for i, m in enumerate(hits[:args.max_per_op]):
            mutated = original[:m.start()] + repl + original[m.end():]
            if mutated == original:
                continue
            open(ref_src, "w").write(mutated)
            killed = not tests_pass(base)   # hidden tests fail => detectable bug
            if killed:
                valid.append((f"{name}#{i}", mutated))
    open(ref_src, "w").write(original)  # restore
    print(f"valid (detectable) mutants: {len(valid)}")

    if not args.candidate:
        print(json.dumps({"valid_mutants": len(valid)}))
        return

    # 3) Score the candidate suite: swap hidden tests for candidate tests, count kills.
    vt = os.path.join(base, "validation-tests")
    shutil.rmtree(vt); os.makedirs(vt)
    # candidate suite must bring its own _discovery or import path; copy candidate files in
    for f in os.listdir(args.candidate):
        shutil.copy(os.path.join(args.candidate, f), os.path.join(vt, f))
    killed = 0
    for mid, msrc in valid:
        open(ref_src, "w").write(msrc)
        if not tests_pass(base):
            killed += 1
    open(ref_src, "w").write(original)
    score = killed / len(valid) if valid else 0.0
    print(json.dumps({"valid_mutants": len(valid), "killed": killed,
                      "mutation_score": round(score, 4)}, indent=2))

if __name__ == "__main__":
    main()
