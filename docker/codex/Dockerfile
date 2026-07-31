FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Install OpenAI Codex CLI. Genuinely pinned now: the comment claimed a pin but
# the command had none, so the image silently froze at 0.141.0 (whatever was
# latest at build time). 0.141 CANNOT run the GPT-5.6 series on subscription
# auth -- OpenAI's backend returns 400 "requires a newer version of Codex" -- and
# it falls back to generic model metadata even via OpenRouter.
# 0.145.0 chosen over 0.146.0: the latter was 50h old at pin time, inside the
# 72h quarantine for new releases. Lifecycle scripts disabled by default; the
# package declares none and ships platform binaries via optionalDependencies.
RUN npm install -g --ignore-scripts @openai/codex@0.145.0

RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
