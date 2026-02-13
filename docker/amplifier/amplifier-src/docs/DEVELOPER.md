# Amplifier Developer Guide

**Use Amplifier to build Amplifier modules.**

As of 10/17/2025, this statement (and contents below) is more aspirational and forward looking than accurate today... but it _is_ where we're going very quickly! Check back soon as we'll have more up-to-date information shortly.

This guide shows you how to leverage Amplifier itself to create custom modules, interfaces, and extensions. The line between "user" and "developer" blurs when AI can generate code from specifications.

> **Note**: Links may break as we reorganize. We're moving fast!

---

## Philosophy: AI Builds Modules

Traditional development: You write every line of code manually.

**Amplifier way**: You specify what you want, Amplifier generates the module code for you.

### Example Workflow

```bash
# 1. Design the module
amplifier run "Use zen-architect to design a module that integrates with GitHub APIs"

# 2. Generate the implementation
amplifier run "Use modular-builder to implement the GitHub tool module based on this spec: [paste design]"

# 3. Test it
amplifier run "Create tests for the GitHub module that cover authentication and API calls"

# 4. Package it
amplifier run "Create a proper pyproject.toml and README for publishing this module"
```

**Result**: A complete, working module with minimal manual coding.

---

## Module Architecture Overview

Amplifier follows a **Linux kernel model**:

- **amplifier-core**: Ultra-thin kernel (mechanisms only, rarely changes)
- **Modules**: Everything else (providers, tools, orchestrators, hooks, context managers)
- **Interfaces**: Stable contracts that modules implement

### Module Types

1. **Orchestrators** - Control the AI execution loop (how the AI processes requests)
2. **Providers** - Connect to AI models (Anthropic, OpenAI, local models, etc.)
3. **Tools** - Add capabilities (file ops, web access, git, databases, etc.)
4. **Hooks** - Extend lifecycle (logging, security, approvals, metrics)
5. **Context Managers** - Handle conversation state (in-memory, persistent, distributed)
6. **Agents** - Specialized sub-sessions (not code modules, but configuration)

---

## Creating a Module with Amplifier

### 1. Design Phase

```bash
amplifier run --mode chat

> I want to create a tool module that integrates with Jira. It should support:
> - Creating issues
> - Updating issues
> - Searching issues
> - Commenting on issues
>
> Use zen-architect to help me design this properly.

[Zen-architect analyzes, provides design spec]

> Save that design to jira-tool-spec.md

[Design saved]
```

### 2. Implementation Phase

```bash
> Now use modular-builder to implement the Jira tool module based on that spec.
> Generate all the necessary files: module code, pyproject.toml, README, tests.

[Modular-builder generates complete module]

> Show me the generated structure

[File listing displayed]
```

### 3. Testing & Refinement

```bash
> Create comprehensive tests for the Jira module

[Tests generated]

> Use bug-hunter to review the code for potential issues

[Bug-hunter identifies edge cases]

> Fix those issues

[Code updated]
```

### 4. Documentation & Publishing

```bash
> Generate a comprehensive README for the Jira module with:
> - Installation instructions
> - Usage examples
> - Configuration options
> - Contribution guidelines

[README generated]

> Create a pyproject.toml suitable for publishing to PyPI

[pyproject.toml generated]
```

**That's it**—you've built a complete Amplifier module with AI assistance at every step.

---

## Module Structure (What Amplifier Generates)

```
amplifier-module-tool-jira/
├── pyproject.toml              # Package metadata, dependencies, entry points
├── README.md                   # Module documentation
├── LICENSE                     # License file
├── amplifier_module_tool_jira/
│   ├── __init__.py            # Entry point with mount() function
│   ├── jira_client.py         # Core implementation
│   └── config.py              # Configuration handling
└── tests/
    ├── test_jira_tool.py      # Unit tests
    └── test_integration.py    # Integration tests
```

### Entry Point Pattern

All modules follow this pattern:

```python
# amplifier_module_tool_jira/__init__.py
from typing import Any
from amplifier_core import ModuleCoordinator

async def mount(coordinator: ModuleCoordinator, config: dict[str, Any] | None = None):
    """
    Mount function called when module is loaded.

    Args:
        coordinator: The module coordinator for registration
        config: Module-specific configuration from bundle

    Returns:
        None
    """
    config = config or {}

    # Create and register your tool
    from .jira_client import JiraTool

    tool = JiraTool(config)
    coordinator.mount('tools', tool, name='jira')

    return None
```

### pyproject.toml Entry Point

```toml
[project]
name = "amplifier-module-tool-jira"
version = "1.0.0"
dependencies = ["jira>=3.0", "amplifier-core"]

[project.entry-points."amplifier.modules"]
tool-jira = "amplifier_module_tool_jira:mount"
```

---

## Manual Development (For Those Who Prefer It)

If you want to build modules manually:

### 1. Study the Reference Implementations

Clone individual module repos and examine their implementations:

```bash
# Clone specific modules you want to study
git clone https://github.com/microsoft/amplifier-module-tool-filesystem
git clone https://github.com/microsoft/amplifier-module-provider-anthropic
```

**Good modules to study:**

- `amplifier-module-tool-filesystem` - Simple, focused tool
- `amplifier-module-provider-anthropic` - Provider integration pattern
- `amplifier-module-loop-basic` - Orchestrator implementation
- `amplifier-module-hooks-logging` - Hook pattern

### 2. Implement the Interface

See [amplifier-core](https://github.com/microsoft/amplifier-core) for interface definitions:

```python
from amplifier_core import Tool, ToolResult

class MyTool(Tool):
    name = "my_tool"
    description = "What this tool does"

    async def execute(self, **kwargs) -> ToolResult:
        """Execute the tool."""
        try:
            # Your implementation
            result = await self.do_work(kwargs)
            return ToolResult(success=True, output=result)
        except Exception as e:
            return ToolResult(
                success=False,
                error={'message': str(e), 'type': type(e).__name__}
            )
```

### 3. Test Thoroughly

```python
import pytest
from amplifier_core.testing import MockCoordinator

@pytest.mark.asyncio
async def test_module_mount():
    coordinator = MockCoordinator()
    await mount(coordinator, {'setting': 'value'})

    # Verify registration
    tools = coordinator.get('tools')
    assert 'my_tool' in tools
```

---

## Publishing Your Module

### To GitHub

```bash
# Create repository
gh repo create amplifier-module-tool-yourname --public

# Push code
git remote add origin git@github.com:yourusername/amplifier-module-tool-yourname
git push -u origin main
```

### Using Your Module

Once published, anyone can use it:

```yaml
# In a bundle
tools:
  - module: tool-yourname
    source: git+https://github.com/yourusername/amplifier-module-tool-yourname@main
```

### Share with Community

Add your module to [MODULES.md](./MODULES.md) in the Community Modules section!

---

## Best Practices

### Module Design

- **Single responsibility** - One module, one clear purpose
- **Stable interfaces** - Follow amplifier-core contracts
- **Graceful errors** - Never crash the kernel
- **Clear configuration** - Document all config options
- **Comprehensive tests** - Cover happy path and error cases

### Security

- **Validate inputs** - Never trust user data
- **Handle secrets safely** - Use environment variables
- **Minimal permissions** - Request only what you need
- **Error visibility** - Log errors, don't hide them

### Performance

- **Async by default** - Use async/await throughout
- **Avoid blocking** - Don't block the event loop
- **Stream when possible** - For long-running operations
- **Cleanup resources** - Close connections, release handles

---

## Resources

**Core Technical Documentation:**

- [amplifier-core](https://github.com/microsoft/amplifier-core) - Kernel interfaces and protocols

**Module Development:**

- See existing modules as templates
- Ask Amplifier to help you build modules
- Join discussions for questions

---

## The Future of Module Development

**Today**: You can use Amplifier to generate module code, but you still need to understand the architecture.

**Tomorrow**: Amplifier will:

- Generate complete modules from natural language descriptions
- Automatically test and validate modules
- Suggest improvements and optimizations
- Handle publishing and versioning
- Create documentation automatically

**The vision**: Tell Amplifier what you want, and it builds the module for you—fully tested, documented, and ready to share. We're getting close!

---

## Example: Building a Database Tool Module

**Conversation with Amplifier:**

```
> I want to build a tool module for PostgreSQL database operations.
> It should support: connecting to databases, running queries, managing schemas.
> Use zen-architect to design this properly following Amplifier conventions.

[Zen-architect provides design spec with error handling, configuration, tests]

> Perfect. Now use modular-builder to generate the complete implementation
> including: module code, pyproject.toml, README.md, comprehensive tests,
> and example usage in a bundle.

[Modular-builder generates all files]

> Show me the generated README

[README displayed]

> Create tests that cover connection errors, query failures, and schema operations

[Tests generated]

> Package this for publishing to GitHub

[Publishing instructions and files generated]
```

**Time to fully functional module**: ~15 minutes (vs hours/days manually)

---

**Ready to build?** Fire up Amplifier and start creating!
