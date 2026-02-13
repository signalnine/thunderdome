---
last_updated: 2025-10-16
status: stable
audience: developer
---

# Local Development Guide

**For developers working on Amplifier modules in the monorepo.**

---

## Architecture Overview

**amplifier-core as Peer Dependency:**
- Modules expect amplifier-core to be **pre-installed**
- They import it but don't bundle it
- This allows using a custom core version

**Module Loading:**
- Loader adds module directories to `sys.path`
- Python imports work if amplifier-core is available
- No traditional pip dependency resolution needed

---

## Quick Start

### 1. Install Development Environment

```bash
cd <your-workspace>
scripts/install-dev.sh
```

This installs all modules in editable mode. The script:
1. Installs core packages using git URLs (required for GitHub installation)
2. **Automatically reinstalls libraries as editable** at the end (for local development)
3. Result: Best of both worlds - GitHub install works + local development uses editable installs

### 2. Configure Local Module Overrides

```bash
# Copy template
cp .amplifier/settings.yaml.template .amplifier/settings.yaml

# Edit to enable modules you're developing
vim .amplifier/settings.yaml
```

**Example:**
```yaml
sources:
  # Working on loop-basic
  loop-basic: file://./amplifier-module-loop-basic

  # Working on provider-anthropic
  provider-anthropic: file://./amplifier-module-provider-anthropic
```

### 3. Run Amplifier

```bash
amplifier run --bundle foundation "test message"
```

The loader will:
- Check Layer 3 (project config) - finds your `.amplifier/settings.yaml`
- Use local paths for overridden modules
- Download others from git (cached)

---

## Common Workflows

### Scenario 1: Developing amplifier-core

```bash
# Install your local core
cd amplifier-core
uv pip install -e .

# Run amplifier - uses YOUR core
cd ..
amplifier run --bundle foundation "test"
```

All modules will import your local core (editable installs have priority).

### Scenario 2: Developing a Module

```bash
# Override just that module
echo "sources:
  tool-bash: file://./amplifier-module-tool-bash" > .amplifier/settings.yaml

# Run amplifier
amplifier run --bundle foundation "test bash"
```

Your local `tool-bash` is used, others come from git.

### Scenario 3: Developing Multiple Modules

```bash
# Override several modules
cat > .amplifier/settings.yaml << EOF
sources:
  loop-basic: file://./amplifier-module-loop-basic
  provider-anthropic: file://./amplifier-module-provider-anthropic
  tool-bash: file://./amplifier-module-tool-bash
EOF

amplifier run --bundle foundation "test"
```

### Scenario 4: Temporary Override (One Command)

```bash
# Use environment variable (Layer 1 - highest priority)
AMPLIFIER_MODULE_TOOL_BASH=./amplifier-module-tool-bash \
  amplifier run --bundle foundation "test bash"
```

---

## Module Resolution Layers

When loading a module, Amplifier checks these locations **in order**:

1. **Environment Variable** - `AMPLIFIER_MODULE_<MODULE_ID>=<path>`
2. **Workspace Convention** - `.amplifier/modules/<module-id>/`
3. **Project Config** - `.amplifier/settings.yaml` ⬅ **Your overrides here**
4. **User Config** - `~/.amplifier/settings.yaml`
5. **Bundle Source** - `source:` field in bundle
6. **Installed Package** - Python package (fallback)

**First match wins.**

See **[Module Resolution User Guide](https://github.com/microsoft/amplifier-module-resolution/blob/main/docs/USER_GUIDE.md)** for details.

---

## Understanding Module Dependencies

### Published Repos (GitHub)

Modules use **git dependencies**:

```toml
# In amplifier-module-tool-bash/pyproject.toml (GitHub)
[tool.uv.sources.amplifier-core]
git = "https://github.com/microsoft/amplifier-core"
branch = "main"
```

**Why:**
- Allows `uv` to validate sources when caching
- Modules cached with `--no-deps` (core not installed from module)
- Core comes from top-level `amplifier` package

### Development Monorepo

**Core packages use git URLs** (even locally):

```toml
# In amplifier-foundation/pyproject.toml
[tool.uv.sources]
amplifier-core = { git = "https://github.com/microsoft/amplifier-core", branch = "main" }
```

**Why git URLs for core packages:**
- **Required for GitHub installation** - Path dependencies break `uv tool install`
- Works for both local development and distribution
- Prevents "subdirectory not found" errors

**How local development works:**
1. `install-dev.sh` installs from git URLs (works correctly)
2. Script then **reinstalls libraries as editable** at the end
3. Result: Local development uses editable installs

**Modules can use path dependencies** (not distributed):

```toml
# In <your-workspace>/amplifier-module-tool-bash/pyproject.toml (local only)
[tool.uv.sources.amplifier-core]
path = "../amplifier-core"
editable = true
```

**Why modules can use paths:**
- Modules distributed via git, not pip
- Faster for local development
- Changes immediately visible

**Rule:** Core packages (foundation, app-cli) → git URLs. Modules → either is fine.

---

## Making Changes

### Workflow

1. **Make changes** in your local module directory
2. **Test locally** using `.amplifier/settings.yaml` overrides
3. **Run module tests**:
   ```bash
   cd amplifier-module-tool-bash
   uv run pytest
   ```
4. **Commit and push** to module's GitHub repo
5. **Update main repo** to point to new commit

### Pushing Module Changes

Modules are git submodules. To push changes:

```bash
cd amplifier-module-tool-bash

# Commit changes
git add .
git commit -m "feat: Add new feature"

# Push to GitHub
git push origin main

# Update main repo
cd ..
git add amplifier-module-tool-bash
git commit -m "chore: Update tool-bash submodule"
git push
```

---

## Troubleshooting

### "Module not found" Error

**Check resolution:**
```bash
amplifier module status tool-bash --verbose
```

Shows all 6 layers and which succeeded/failed.

**Common fixes:**
- Add override to `.amplifier/settings.yaml`
- Check path is correct (relative to repo root)
- Ensure module has valid Python code

### Import Errors for amplifier_core

**Problem:** Module can't import amplifier_core

**Solution:** Install local core:
```bash
cd amplifier-core
uv pip install -e .
```

### Changes Not Reflected

**Problem:** Made changes but old code runs

**Common causes:**
1. **Python cached bytecode** - Run: `find . -type d -name __pycache__ -exec rm -rf {} +`
2. **Wrong override** - Check `.amplifier/settings.yaml` paths
3. **Module not overridden** - Add to settings.yaml

### Git Submodule Issues

**Update all submodules:**
```bash
git submodule update --init --recursive
```

**Pull latest for all modules:**
```bash
git submodule foreach git pull origin main
```

---

## Best Practices

### 1. Use Minimal Overrides

Only override modules you're actively developing:

```yaml
# Good - focused
sources:
  tool-bash: file://./amplifier-module-tool-bash

# Avoid - unnecessary
sources:
  tool-bash: file://./amplifier-module-tool-bash
  tool-filesystem: file://./amplifier-module-tool-filesystem
  tool-web: file://./amplifier-module-tool-web
  # ... 15 more modules you're not touching
```

### 2. Keep .amplifier/settings.yaml Local

**Don't commit** `.amplifier/settings.yaml` - it's personal to your dev setup.

The template is committed for reference.

### 3. Test With and Without Overrides

Before pushing:

```bash
# Test with your changes
amplifier run --bundle foundation "test"

# Test without overrides (simulates production)
mv .amplifier/settings.yaml .amplifier/settings.yaml.bak
amplifier module refresh --all
amplifier run --bundle foundation "test"
mv .amplifier/settings.yaml.bak .amplifier/settings.yaml
```

### 4. Clear Cache When Switching Branches

```bash
# After checking out different branch - use reset to safely clear cache
amplifier reset --remove cache -y

# Or use interactive mode to choose what to preserve
amplifier reset
```

**WARNING**: Never manually delete `~/.amplifier/cache/` - the Amplifier CLI has editable install dependencies in this directory. Use `amplifier reset` which handles cache clearing safely and reinstalls dependencies.

---

## Related Documentation

- **[Module Resolution User Guide](https://github.com/microsoft/amplifier-module-resolution/blob/main/docs/USER_GUIDE.md)** - Customizing module sources
- [MODULE_DEVELOPMENT.md](./MODULE_DEVELOPMENT.md) - Creating modules
- **[Module Resolution Specification](https://github.com/microsoft/amplifier-module-resolution/blob/main/docs/SPECIFICATION.md)** - Technical specification
