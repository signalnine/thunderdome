---
last_updated: 2025-10-16
status: stable
audience: developer
---

# Testing Guide

This guide explains how to test Amplifier modules and ensure code quality.

## Testing Philosophy

**From AGENTS.md:**

> Tests should catch real bugs, not duplicate code inspection:
>
> - ✅ Write tests for: Runtime invariants, edge cases, integration behavior, convention enforcement
> - ❌ Don't test: Things obvious from reading code

**Key principle:** If code inspection is faster than maintaining a test, skip the test.

## Test Organization

### Directory Structure

```
amplifier-module-*/
├── src/
│   └── amplifier_module_*/
│       ├── __init__.py
│       └── ...
├── tests/
│   ├── __init__.py
│   ├── test_unit.py          # Unit tests
│   ├── test_integration.py   # Integration tests
│   └── fixtures/             # Test data
├── pyproject.toml
└── README.md
```

### Test Categories

1. **Unit Tests** - Test individual functions/classes in isolation
2. **Integration Tests** - Test module integration with amplifier-core
3. **End-to-End Tests** - Test complete workflows

**Testing pyramid:**

- 60% unit tests
- 30% integration tests
- 10% end-to-end tests

## Running Tests

### Basic Commands

```bash
# Run all tests for a module
cd amplifier-module-tool-filesystem
uv run pytest

# Run with verbose output
uv run pytest -v

# Run specific test file
uv run pytest tests/test_unit.py

# Run specific test function
uv run pytest tests/test_unit.py::test_function_name -v

# Run with coverage
uv run pytest --cov=amplifier_module_tool_filesystem

# Run fast tests only (skip slow integration tests)
uv run pytest -m "not slow"
```

## Writing Tests

### Unit Test Example

```python
# tests/test_filesystem_tool.py
import pytest
from pathlib import Path
from amplifier_module_tool_filesystem import FilesystemTool

def test_read_file_success():
    """Test reading an existing file."""
    tool = FilesystemTool()
    content = tool.read_file("tests/fixtures/sample.txt")
    assert "expected content" in content

def test_read_file_not_found():
    """Test error handling for missing file."""
    tool = FilesystemTool()
    with pytest.raises(FileNotFoundError):
        tool.read_file("nonexistent.txt")

@pytest.mark.parametrize("filename,expected", [
    ("test.txt", True),
    ("test.py", True),
    ("../../../etc/passwd", False),  # Path traversal
])
def test_path_validation(filename, expected):
    """Test path validation prevents directory traversal."""
    tool = FilesystemTool()
    result = tool.is_safe_path(filename)
    assert result == expected
```

### Integration Test Example

```python
# tests/test_integration.py
import pytest
from amplifier_core import AmplifierSession
from amplifier_module_tool_filesystem import FilesystemTool

@pytest.mark.integration
async def test_tool_execution_in_session():
    """Test tool works correctly when called via session."""
    session = AmplifierSession()
    tool = FilesystemTool()

    # Mount tool
    await session.mount_tool("filesystem", tool)

    # Execute tool
    result = await session.execute_tool(
        "filesystem",
        "read_file",
        {"path": "tests/fixtures/sample.txt"}
    )

    assert result.success
    assert "expected content" in result.output
```

### Fixtures

```python
# tests/conftest.py
import pytest
from pathlib import Path
import tempfile

@pytest.fixture
def temp_dir():
    """Create temporary directory for tests."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)

@pytest.fixture
def sample_file(temp_dir):
    """Create sample file for testing."""
    file_path = temp_dir / "sample.txt"
    file_path.write_text("Sample content")
    return file_path

@pytest.fixture
async def mock_session():
    """Create mock Amplifier session."""
    from unittest.mock import AsyncMock
    session = AsyncMock()
    session.execute_tool = AsyncMock(return_value={"success": True})
    return session
```

## Testing Different Module Types

### Testing Tool Modules

Key aspects to test:

- Tool execution with valid inputs
- Error handling for invalid inputs
- Permission checks
- Resource cleanup
- Event emission

```python
def test_tool_execution():
    """Test tool executes correctly."""
    tool = MyTool()
    result = tool.execute({"arg": "value"})
    assert result["success"]

def test_tool_permission_check():
    """Test tool respects permission settings."""
    tool = MyTool(require_approval=True)
    result = tool.execute({"sensitive": "operation"})
    assert result["approval_required"]

def test_tool_emits_events():
    """Test tool emits correct lifecycle events."""
    events = []
    tool = MyTool(event_handler=events.append)

    tool.execute({"arg": "value"})

    assert any(e["event"] == "tool:pre" for e in events)
    assert any(e["event"] == "tool:post" for e in events)
```

### Testing Provider Modules

Key aspects to test:

- Completion generation
- Error handling (rate limits, timeouts)
- Token counting
- Streaming responses
- Capability reporting

```python
import pytest
from unittest.mock import AsyncMock, patch

@pytest.mark.asyncio
async def test_provider_complete():
    """Test basic completion."""
    provider = MyProvider(api_key="test-key")

    with patch.object(provider.client, "messages",
                     return_value=AsyncMock(content="response")):
        result = await provider.complete(messages=[
            {"role": "user", "content": "Hello"}
        ])

    assert result.content == "response"

@pytest.mark.asyncio
async def test_provider_handles_rate_limit():
    """Test provider handles rate limit errors."""
    provider = MyProvider(api_key="test-key")

    with patch.object(provider.client, "messages",
                     side_effect=RateLimitError()):
        with pytest.raises(RateLimitError):
            await provider.complete(messages=[])
```

### Testing Orchestrator Modules

Key aspects to test:

- Turn execution
- Tool call handling
- Context management
- Event emission

```python
@pytest.mark.asyncio
async def test_orchestrator_single_turn():
    """Test orchestrator handles single turn correctly."""
    orchestrator = MyOrchestrator()

    result = await orchestrator.execute_turn(
        prompt="Test prompt",
        context=mock_context
    )

    assert result.completed
    assert result.response is not None
```

### Testing Hook Modules

Key aspects to test:

- Event handling
- Non-interference (hooks don't crash session)
- Correct data capture/transformation

```python
def test_hook_handles_event():
    """Test hook processes events correctly."""
    hook = MyHook()
    events_captured = []

    hook.on_event("session:start", {"session_id": "123"},
                 capture=events_captured.append)

    assert len(events_captured) == 1
    assert events_captured[0]["session_id"] == "123"

def test_hook_doesnt_crash_on_error():
    """Test hook errors don't propagate to session."""
    hook = MyHook()

    # Should not raise even if hook fails internally
    hook.on_event("bad:event", {"malformed": None})
```

## Mocking & Test Doubles

### Mocking External APIs

```python
from unittest.mock import patch, MagicMock

def test_with_mocked_api():
    """Test module behavior with mocked external API."""
    with patch('requests.get') as mock_get:
        mock_get.return_value.json.return_value = {"data": "test"}

        tool = WebTool()
        result = tool.fetch("https://example.com")

        assert result["data"] == "test"
        mock_get.assert_called_once()
```

### Mock Providers

```python
# Use provider-mock for testing
from amplifier_module_provider_mock import MockProvider

@pytest.fixture
def mock_provider():
    """Create mock provider for testing."""
    return MockProvider(
        default_response="Mocked response",
        response_delay=0.0,
        fail_probability=0.0
    )

def test_with_mock_provider(mock_provider):
    """Test behavior with predictable provider."""
    result = await mock_provider.complete([
        {"role": "user", "content": "test"}
    ])
    assert result.content == "Mocked response"
```

## Testing Best Practices

### 1. Test Naming

```python
# Good: Descriptive, action-oriented
def test_read_file_returns_content_when_file_exists():
    pass

# Bad: Vague
def test_read():
    pass
```

### 2. Arrange-Act-Assert Pattern

```python
def test_example():
    # Arrange - Set up test data
    tool = FilesystemTool()
    test_file = "test.txt"

    # Act - Execute the operation
    result = tool.read_file(test_file)

    # Assert - Verify expectations
    assert result is not None
    assert len(result) > 0
```

### 3. One Assertion Per Test

```python
# Prefer focused tests
def test_file_read_succeeds():
    result = read_file("test.txt")
    assert result.success

def test_file_read_returns_content():
    result = read_file("test.txt")
    assert "expected" in result.content

# Over one test with multiple assertions
```

### 4. Test Edge Cases

```python
def test_empty_input():
    """Test handling of empty input."""
    result = process("")
    assert result is not None

def test_very_large_input():
    """Test handling of large input."""
    result = process("x" * 1000000)
    assert result.success

def test_special_characters():
    """Test handling of special characters."""
    result = process("test\n\r\t<>&")
    assert result.success
```

### 5. Use Markers

```python
import pytest

@pytest.mark.slow
def test_expensive_operation():
    """Test that takes a long time."""
    pass

@pytest.mark.integration
def test_with_external_service():
    """Test requiring external dependencies."""
    pass

@pytest.mark.skip(reason="Feature not implemented yet")
def test_future_feature():
    pass
```

## Continuous Integration

### GitHub Actions Example

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: [3.11, 3.12]

    steps:
      - uses: actions/checkout@v3

      - name: Install uv
        run: curl -LsSf https://astral.sh/uv/install.sh | sh

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ matrix.python-version }}

      - name: Install dependencies
        run: |
          cd amplifier-module-*/
          uv sync --dev

      - name: Run tests
        run: |
          cd amplifier-module-*/
          uv run pytest --cov --cov-report=xml

      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

## Coverage Goals

- **Minimum:** 70% code coverage
- **Target:** 85% code coverage
- **Critical paths:** 100% coverage

```bash
# Generate coverage report
uv run pytest --cov --cov-report=html

# View report
open htmlcov/index.html
```

## Common Testing Patterns

### Testing File Operations

```python
import tempfile
from pathlib import Path

def test_file_write():
    """Test writing to file."""
    with tempfile.TemporaryDirectory() as tmpdir:
        file_path = Path(tmpdir) / "test.txt"

        tool = FilesystemTool()
        tool.write_file(str(file_path), "content")

        assert file_path.exists()
        assert file_path.read_text() == "content"
```

### Testing Async Code

```python
import pytest

@pytest.mark.asyncio
async def test_async_function():
    """Test async function."""
    result = await async_operation()
    assert result.success
```

### Testing Exceptions

```python
def test_raises_exception():
    """Test that exception is raised correctly."""
    with pytest.raises(ValueError, match="Invalid input"):
        dangerous_function("bad input")
```

## Debugging Failed Tests

### Test Runner Debugging

```bash
# Run with extra verbosity
uv run pytest -vv

# Stop at first failure
uv run pytest -x

# Drop into debugger on failure
uv run pytest --pdb

# Show local variables on failure
uv run pytest -l

# Rerun only failed tests
uv run pytest --lf
```

### LLM Provider Debugging

When debugging issues with LLM providers, enable DEBUG-level logging to see full request/response details:

```yaml
# In your bundle or config
providers:
  - module: provider-anthropic
    config:
      debug: true # Enable detailed LLM I/O logging

hooks:
  - module: hooks-logging
    config:
      level: "DEBUG" # Capture debug events
```

This logs:

- `llm:request:debug` - Complete request with all messages
- `llm:response:debug` - Full response with content and usage

Logs appear in: `~/.amplifier/projects/<project>/sessions/<session_id>/events.jsonl`

**See**: [hooks-logging module documentation](../amplifier-module-hooks-logging/README.md#debug) for complete DEBUG logging details.

**Visualize logs**: Use [amplifier-app-log-viewer](https://github.com/microsoft/amplifier-app-log-viewer) for interactive log inspection:

```bash
# Run the log viewer (separate terminal)
uvx --from git+https://github.com/microsoft/amplifier-app-log-viewer@main amplifier-log-viewer

# View logs in browser at http://localhost:8180
# - Real-time updates as Amplifier runs
# - Interactive JSON viewer with expand/collapse
# - Smart filtering by event type and level
```

## Related Documentation

- [MODULE_DEVELOPMENT.md](MODULE_DEVELOPMENT.md) - Module development guide
- [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) - Development environment setup
- [AGENTS.md](../AGENTS.md) - Testing philosophy from project context

## Summary

**Key Testing Principles:**

1. **Test behavior, not implementation** - Focus on what code does, not how
2. **Write tests that catch real bugs** - Avoid testing obvious code
3. **Keep tests simple and focused** - One test, one concept
4. **Use appropriate test doubles** - Mock external dependencies
5. **Follow the testing pyramid** - More unit tests, fewer E2E tests

**Quick Commands:**

```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov

# Run fast tests only
uv run pytest -m "not slow"

# Debug failing test
uv run pytest tests/test_file.py::test_name -vv --pdb
```
