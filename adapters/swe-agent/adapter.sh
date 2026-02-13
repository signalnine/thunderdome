#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so sweagent can write config/trajectory files
export HOME=/tmp

# Fix git state for SWE-Agent:
# - Remove remote origin (points to host filesystem, inaccessible from container)
# - Create a proper branch from detached HEAD (SWE-Agent expects a branch)
git remote remove origin 2>/dev/null || true
git checkout -b main 2>/dev/null || true

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

set +e
sweagent run \
  --agent.model.name=claude-sonnet-4-20250514 \
  --agent.model.per_instance_cost_limit=5.00 \
  --env.repo.type=preexisting \
  --env.repo.repo_name=workspace \
  --env.repo.base_commit=HEAD \
  --env.deployment.type=local \
  --problem_statement.type=text \
  --problem_statement.text="$TASK_PROMPT" \
  2>&1 | tee /workspace/.thunderdome-output.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

exit $EXIT_CODE
