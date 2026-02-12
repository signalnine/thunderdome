FROM node:20-bookworm

# Pin Claude Code version for reproducibility
RUN npm install -g @anthropic-ai/claude-code@2.1.39

# Install Python and LiteLLM proxy
RUN apt-get update && apt-get install -y python3-pip python3-venv && rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages litellm[proxy]

# Git config (Claude Code needs this for tool use)
RUN git config --global user.name "Thunderdome" && \
    git config --global user.email "bench@localhost"

# LiteLLM config: maps all Claude model names to gemini-2.0-flash
COPY litellm-config.yaml /opt/litellm-config.yaml

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
