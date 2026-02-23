FROM thunderdome/claude-code:latest

# Upgrade Claude Code to latest (2.1.42) for agent teams support
RUN npm install -g @anthropic-ai/claude-code@latest

# Tools for driving interactive Claude Code
RUN apt-get update -qq && \
    apt-get install -y -qq tmux procps && \
    rm -rf /var/lib/apt/lists/*
