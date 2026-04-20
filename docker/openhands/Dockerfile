FROM python:3.12-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    ripgrep \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Node for JS benchmarks
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install OpenHands CLI via pip (uv has seccomp issues during Docker build)
RUN pip install --no-cache-dir --root-user-action=ignore openhands
ENV OPENHANDS_SUPPRESS_BANNER=1

RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
