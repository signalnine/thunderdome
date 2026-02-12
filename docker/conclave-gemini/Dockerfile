FROM thunderdome/claude-code-gemini:latest

# Copy the Conclave plugin
COPY conclave-plugin /opt/conclave-plugin

# Ensure the conclave binary is executable
RUN chmod +x /opt/conclave-plugin/conclave
