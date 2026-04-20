FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    ripgrep \
    curl \
    bzip2 \
    && rm -rf /var/lib/apt/lists/*

# Download Goose binary (Block/AAIF's Rust coding agent, Terminal-Bench rank 45)
ADD https://github.com/aaif-goose/goose/releases/latest/download/goose-x86_64-unknown-linux-gnu.tar.bz2 /tmp/goose.tar.bz2
RUN tar xjf /tmp/goose.tar.bz2 -C /usr/local/bin && \
    chmod +x /usr/local/bin/goose && \
    rm /tmp/goose.tar.bz2

RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
