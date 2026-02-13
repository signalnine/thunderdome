# hooks-session-naming

Automatic session naming and description generation for Amplifier sessions.

## Overview

This hook module observes conversation progress and automatically generates human-readable session names and descriptions using the configured LLM provider. Names and descriptions are stored in the session's `metadata.json` for display in CLI, log-viewer, and other UIs.

## Features

- **Automatic naming**: Generates session name after 2 turns (configurable)
- **Description updates**: Periodically updates description as conversation evolves
- **Non-blocking**: All LLM calls run in background, never blocking the main conversation
- **Smart context extraction**: Uses bookend+sampling for long conversations
- **Graceful deferral**: Waits for more context if initial turns are too vague

## Configuration

```yaml
hooks:
  - module: hooks-session-naming
    source: git+https://github.com/microsoft/amplifier-foundation@main#subdirectory=modules/hooks-session-naming
    config:
      initial_trigger_turn: 2        # Generate name after this turn (default: 2)
      update_interval_turns: 5       # Update description every N turns (default: 5)
      max_name_length: 50            # Maximum name length (default: 50)
      max_description_length: 200    # Maximum description length (default: 200)
      max_retries: 3                 # Max retries on defer (default: 3)
```

## How It Works

1. After turn 2, the hook spawns a background task to generate a session name
2. If the LLM signals "defer" (insufficient context), it retries on subsequent turns
3. Once named, the hook periodically checks if the description needs updating
4. Updates only occur when scope meaningfully expands (stability-first approach)

## Metadata Fields

The hook adds these fields to `metadata.json`:

```json
{
  "name": "Auth bug investigation",
  "description": "Debugging OAuth2 token refresh race conditions",
  "name_generated_at": "2024-01-07T12:05:00Z",
  "description_updated_at": "2024-01-07T12:30:00Z"
}
```
