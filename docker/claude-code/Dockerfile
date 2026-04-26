FROM node:20-bookworm

# Install system deps (python3 for proxy scripts, curl for health checks,
# tmux for interactive-mode adapters that drive `claude` in a remote-controlled pane).
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    curl \
    tmux \
    && rm -rf /var/lib/apt/lists/*

# Pin Claude Code version for reproducibility
# Bumped 2.1.39 -> 2.1.119 on 2026-04-25 to gain --bare (required by tmux-driven
# interactive adapters; lets `claude` run without the first-run OAuth wizard).
# Newer claude-code ships a native binary that postinstall (install.cjs) must
# run to materialize. The postinstall hits EACCES under buildkit's default
# seccomp profile, so install with --ignore-scripts then run the install step
# manually with bash explicitly.
RUN npm install -g --ignore-scripts @anthropic-ai/claude-code@2.1.119 && \
    cd /usr/local/lib/node_modules/@anthropic-ai/claude-code && \
    bash -c "node install.cjs"

# Git config (Claude Code needs this for tool use)
RUN git config --global user.name "Thunderdome" && \
    git config --global user.email "bench@localhost"

# Headless handler: wraps Claude Code to auto-respond to interactive tool
# invocations (AskUserQuestion, EnterPlanMode, Skill) in benchmark mode.
COPY headless-handler.js /opt/headless-handler.js
COPY anthropic_proxy.py /usr/local/bin/anthropic_proxy.py
RUN chmod +x /usr/local/bin/anthropic_proxy.py
COPY anth2openai_proxy.py /usr/local/bin/anth2openai_proxy.py
RUN chmod +x /usr/local/bin/anth2openai_proxy.py

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
