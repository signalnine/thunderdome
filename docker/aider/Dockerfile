FROM node:20-bookworm

# Aider needs Python
RUN apt-get update && \
    apt-get install -y python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

# Pin Aider version for reproducibility
RUN pip install --break-system-packages aider-chat==0.86.1

# Git config
RUN git config --global user.name "Thunderdome" && \
    git config --global user.email "bench@localhost"

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
