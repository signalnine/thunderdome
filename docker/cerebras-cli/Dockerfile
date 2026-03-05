FROM node:20-bookworm

# Install ripgrep and fzf
RUN apt-get update && apt-get install -y ripgrep fzf && rm -rf /var/lib/apt/lists/*

# Install bun binary directly (npm install fails due to AppArmor in build)
ADD https://github.com/oven-sh/bun/releases/latest/download/bun-linux-x64.zip /tmp/bun.zip
RUN apt-get update && apt-get install -y unzip && rm -rf /var/lib/apt/lists/* && \
    unzip /tmp/bun.zip -d /tmp && \
    mv /tmp/bun-linux-x64/bun /usr/local/bin/bun && \
    chmod +x /usr/local/bin/bun && \
    rm -rf /tmp/bun.zip /tmp/bun-linux-x64

# Install cerebras-cli globally (skip postinstall, run it separately)
RUN npm install -g --ignore-scripts cerebras-cli@1.1.98 && \
    cd /usr/local/lib/node_modules/cerebras-cli && \
    node ./postinstall.mjs

# Git config
RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
