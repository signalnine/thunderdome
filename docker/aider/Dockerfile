FROM node:20-bookworm

# Aider needs Python
RUN apt-get update && \
    apt-get install -y python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

# Pin Aider version for reproducibility
RUN pip install --break-system-packages aider-chat==0.86.1

# OpenAI-compatible proxy (reasoning-delta stripping, developer->system rewrite,
# browser User-Agent for Cloudflare bypass).
COPY openai_proxy.py /usr/local/bin/openai_proxy.py
RUN chmod +x /usr/local/bin/openai_proxy.py

# Git config
RUN git config --global user.name "Thunderdome" && \
    git config --global user.email "bench@localhost"

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
