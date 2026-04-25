FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# grok-agent: coding-focused xAI Grok CLI (github.com/superagent-ai/grok-agent)
RUN npm install -g grok-agent@0.8.1

RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
