# Installing Conclave for Codex

Quick setup to enable conclave skills in Codex.

## Installation

1. **Clone conclave repository**:
   ```bash
   mkdir -p ~/.codex/conclave
   cd ~/.codex/conclave
   git clone https://github.com/signalnine/conclave.git .
   ```

2. **Create personal skills directory**:
   ```bash
   mkdir -p ~/.codex/skills
   ```

3. **Update ~/.codex/AGENTS.md** to include this conclave section:
   ```markdown
   ## Conclave System

   <EXTREMELY_IMPORTANT>
   You have conclave. Conclave teaches you new skills and capabilities. RIGHT NOW run: `~/.codex/conclave/.codex/conclave-codex bootstrap` and follow the instructions it returns.
   </EXTREMELY_IMPORTANT>
   ```

## Verification

Test the installation:
```bash
~/.codex/conclave/.codex/conclave-codex bootstrap
```

You should see skill listings and bootstrap instructions. The system is now ready for use.
