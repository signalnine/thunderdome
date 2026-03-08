FROM node:20-bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy pre-downloaded crush binary from host
COPY bin/crush /usr/local/bin/crush
RUN chmod +x /usr/local/bin/crush

# Use /tmp as HOME so Crush can write config/session files
ENV HOME=/tmp
ENV CRUSH_DISABLE_PROVIDER_AUTO_UPDATE=1
RUN mkdir -p /tmp/.config/crush /tmp/.local/share/crush && \
    chmod -R 777 /tmp/.config /tmp/.local/share

# Copy crush provider and config files
COPY providers.json /tmp/.local/share/crush/providers.json
COPY crush.json /tmp/.local/share/crush/crush.json
RUN chmod 666 /tmp/.local/share/crush/providers.json /tmp/.local/share/crush/crush.json

WORKDIR /workspace

CMD ["/bin/bash", "/adapter.sh"]
