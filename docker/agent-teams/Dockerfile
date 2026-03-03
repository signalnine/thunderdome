FROM thunderdome/claude-code:latest

# Upgrade Claude Code to latest for agent teams support
RUN npm install -g @anthropic-ai/claude-code@latest

# Tools for driving interactive Claude Code
RUN apt-get update -qq && \
    apt-get install -y -qq tmux procps gosu && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user with UID 1000 (matches 'node' user from base image AND
# the host user UID that the harness passes via --user flag).
# Claude Code >=2.1.x blocks --dangerously-skip-permissions as root.
# We reuse the existing 'node' user (uid 1000) since the harness runs containers
# as uid 1000 and we need the adapter user to own the workspace files.
RUN usermod -l claude -d /home/claude -m node && \
    groupmod -n claude node && \
    mkdir -p /workspace && chown claude:claude /workspace

# Git config for the non-root user
RUN su - claude -c 'git config --global user.name "Thunderdome" && git config --global user.email "bench@localhost"'
