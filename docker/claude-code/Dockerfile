FROM node:20-bookworm

# Install system deps (python3 for proxy scripts, curl for health checks)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Pin Claude Code version for reproducibility
RUN npm install -g @anthropic-ai/claude-code@2.1.39

# Git config (Claude Code needs this for tool use)
RUN git config --global user.name "Thunderdome" && \
    git config --global user.email "bench@localhost"

# Headless handler: wraps Claude Code to auto-respond to interactive tool
# invocations (AskUserQuestion, EnterPlanMode, Skill) in benchmark mode.
COPY headless-handler.js /opt/headless-handler.js
COPY anthropic_proxy.py /usr/local/bin/anthropic_proxy.py
RUN chmod +x /usr/local/bin/anthropic_proxy.py

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
