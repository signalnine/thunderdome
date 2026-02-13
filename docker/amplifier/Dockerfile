FROM node:20-bookworm

# Python for Amplifier
RUN apt-get update && \
    apt-get install -y python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

# uv is needed by Amplifier for bundle management
RUN pip install --break-system-packages uv

# Install Amplifier and its dependencies in order
COPY amplifier-core /opt/amplifier-core
RUN pip install --break-system-packages /opt/amplifier-core

COPY amplifier-foundation /opt/amplifier-foundation
RUN pip install --break-system-packages /opt/amplifier-foundation

COPY amplifier-app-cli /opt/amplifier-app-cli
RUN pip install --break-system-packages /opt/amplifier-app-cli

COPY amplifier-src /opt/amplifier
RUN pip install --break-system-packages /opt/amplifier

# Pre-install Anthropic provider module (entry-point based discovery)
COPY amplifier-provider-anthropic /opt/amplifier-provider-anthropic
RUN pip install --break-system-packages /opt/amplifier-provider-anthropic

# Allow non-root users to install Python packages at runtime
# (Amplifier's bundle system needs to install packages dynamically)
RUN rm -f /usr/lib/python3.11/EXTERNALLY-MANAGED && \
    chmod -R a+w /usr/local/lib/python3.11/dist-packages/ && \
    chmod -R a+w /usr/local/bin/

# Git config (use --system so it works for any UID)
RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
