FROM node:20-bookworm-slim

# Install system dependencies including Python for proxy
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install litellm proxy (translates OpenAI API to ollama native API properly)
RUN pip3 install --break-system-packages 'litellm[proxy]<1.82.7'

# Copy pre-downloaded crush binary from host
COPY bin/crush /usr/local/bin/crush
RUN chmod +x /usr/local/bin/crush

# Copy the OpenAI-compatible proxy script
COPY openai_proxy.py /usr/local/bin/openai_proxy.py
RUN chmod +x /usr/local/bin/openai_proxy.py

# Use /tmp as HOME so Crush can write config/session files
ENV HOME=/tmp
ENV CRUSH_DISABLE_PROVIDER_AUTO_UPDATE=1
RUN mkdir -p /tmp/.config/crush /tmp/.local/share/crush && \
    chmod -R 777 /tmp/.config /tmp/.local/share

# Copy crush provider and config files (will be modified at runtime to use proxy)
COPY providers.json /tmp/.local/share/crush/providers.json
COPY crush.json /tmp/.local/share/crush/crush.json
RUN chmod 666 /tmp/.local/share/crush/providers.json /tmp/.local/share/crush/crush.json

WORKDIR /workspace

CMD ["/bin/bash", "/adapter.sh"]
