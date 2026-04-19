FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    ripgrep \
    fzf \
    curl \
    expect \
    && rm -rf /var/lib/apt/lists/*

# Install Forge Code binary directly from GitHub releases (install script requires
# network during Docker build, which often fails; pulling the binary directly is
# more reliable and lets Docker cache the layer).
ADD https://github.com/tailcallhq/forgecode/releases/latest/download/forge-x86_64-unknown-linux-musl /usr/local/bin/forge
RUN chmod +x /usr/local/bin/forge

RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
