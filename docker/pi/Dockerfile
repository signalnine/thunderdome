FROM oven/bun:1 AS bun-base

FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    ripgrep \
    fzf \
    unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=bun-base /usr/local/bin/bun /usr/local/bin/bun
RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx

# Vanilla pi (upstream, not oh-my-pi)
RUN bun install -g @mariozechner/pi-coding-agent && \
    chmod a+rx /root && \
    chmod -R a+rX /root/.bun
ENV PATH="/root/.bun/bin:${PATH}"

# Copy OpenAI-compatible proxy (rewrites developer->system role for vLLM compat).
COPY openai_proxy.py /usr/local/bin/openai_proxy.py
RUN chmod +x /usr/local/bin/openai_proxy.py

RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
