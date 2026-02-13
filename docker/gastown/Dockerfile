FROM thunderdome/claude-code:latest

# tmux is required for Gas Town's polecat session management
RUN apt-get update && \
    apt-get install -y tmux sqlite3 && \
    rm -rf /var/lib/apt/lists/*

# Install Gas Town (gt) and Beads (bd) pre-built binaries
COPY gt /usr/local/bin/gt
COPY bd /usr/local/bin/bd
RUN chmod +x /usr/local/bin/gt /usr/local/bin/bd

# Pre-configure Claude Code to skip first-run onboarding (theme picker).
# Gas Town runs Claude in interactive tmux sessions, which trigger onboarding.
# Without this, the theme picker blocks the polecat from starting work.
RUN mkdir -p /home/node/.claude && \
    echo '{"theme":"dark","hasCompletedOnboarding":true}' > /home/node/.claude/settings.json && \
    echo '{"hasCompletedOnboarding":true}' > /home/node/.claude.json && \
    chown -R 1000:1000 /home/node/.claude /home/node/.claude.json

# Git config: use --system so it works for any UID
# (claude-code base image uses --global which may not apply to UID 1000)
RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory '*'

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
