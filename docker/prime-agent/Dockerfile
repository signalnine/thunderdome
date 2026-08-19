FROM node:22-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    python3-venv \
    ripgrep \
    fd-find \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Prime Agent (PrimeIntellect-ai/prime-agent) v0.7.3, MIT.
#
# Installed from VENDORED, CHECKSUM-VERIFIED release artifacts. Deliberately NOT
# via the upstream `curl -fsSL .../install.sh | sh` documented in the README, and
# deliberately NOT resolving pi-agent-core / pi-ai / pi-tui from the mutable
# Cloudflare R2 bucket that the package's own package.json points at. Those three
# R2 tarballs were byte-compared against the project's checksummed GitHub release
# assets at vendoring time and matched exactly; pinning the local copies means a
# later rebuild cannot silently pull different bytes from the same URL.
#
# SECURITY POSTURE: Prime Agent's design is to execute MODEL-GENERATED PYTHON and
# project commands with the invoking user's permissions -- persistent IPython is
# its primary tool, not a fixed tool schema. That is acceptable here only because
# the container is the sandbox, the same rationale as Claude Code's
# --dangerously-skip-permissions. Do not run this adapter outside a container.
COPY vendor/ /tmp/vendor/
RUN cd /tmp/vendor \
    && sha256sum -c SHA256SUMS --ignore-missing \
    && npm install -g --ignore-scripts ./prime-agent-0.7.3.tgz \
    && rm -rf /tmp/vendor

# Bootstrap the IPython kernel at BUILD time rather than letting it fetch on
# first use inside each trial container. This runs the package's own
# postinstall path explicitly (it is a no-op unless these env vars are set), so
# we get the vendor's correct kernel setup as a visible, reproducible layer
# instead of a hidden lifecycle script -- and trials get no runtime network
# dependency and no first-trial latency skew.
ENV PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 \
    PRIME_AGENT_BOOTSTRAP_TOOLS_ON_INSTALL=1 \
    PRIME_AGENT_INSTALL_UV=1
RUN node /usr/local/lib/node_modules/prime-agent/dist/postinstall.js || \
    echo "prime-agent: kernel bootstrap reported an issue; runtime fallback will apply"
ENV PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=0 \
    PRIME_AGENT_BOOTSTRAP_TOOLS_ON_INSTALL=0

RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace
