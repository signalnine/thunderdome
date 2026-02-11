FROM node:20-bookworm

# Pin Claude Code version for reproducibility
RUN npm install -g @anthropic-ai/claude-code@2.1.39

# Git config (Claude Code needs this for tool use)
RUN git config --global user.name "Thunderdome" && \
    git config --global user.email "bench@localhost"

# Install netcat for port polling in adapter script
RUN apt-get update && apt-get install -y netcat-openbsd && rm -rf /var/lib/apt/lists/*

# Copy pre-built Go WebSocket server (static binary)
COPY ws-server /opt/ws-server
RUN chmod +x /opt/ws-server

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
