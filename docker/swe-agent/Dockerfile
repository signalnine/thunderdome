FROM node:20-bookworm

# Python for SWE-Agent
RUN apt-get update && \
    apt-get install -y python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

# Install SWE-Agent from local copy (v1.1.0) in editable mode
# so tool bundle paths resolve relative to /opt/swe-agent/
COPY swe-agent-src /opt/swe-agent
RUN cd /opt/swe-agent && pip install --break-system-packages -e .

# Trajectories dir needs to be writable at runtime
RUN mkdir -p /opt/swe-agent/trajectories

# SWE-Agent hardcodes /root/ for tool installation and state files.
# Make it writable for non-root users (container runs as host UID).
RUN chmod 777 /root

# Remove PEP 668 marker and make packages writable for tool installations
RUN rm -f /usr/lib/python3.11/EXTERNALLY-MANAGED && \
    chmod -R a+w /usr/local/lib/python3.11/dist-packages/ && \
    chmod -R a+w /usr/local/bin/

# Git config (use --system so it works for any UID)
RUN git config --system user.name "Thunderdome" && \
    git config --system user.email "bench@localhost" && \
    git config --system --add safe.directory /opt/swe-agent && \
    git config --system --add safe.directory /workspace

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
