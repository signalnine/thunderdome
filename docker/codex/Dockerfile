FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Install OpenAI Codex CLI (pinned for reproducibility; remove pin to track latest)
RUN npm install -g @openai/codex

RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
