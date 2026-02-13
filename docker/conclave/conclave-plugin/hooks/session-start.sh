#!/usr/bin/env bash
# SessionStart hook for conclave plugin

set -euo pipefail

# Determine plugin root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check if legacy skills directory exists and build warning
warning_message=""
legacy_skills_dir="${HOME}/.config/conclave/skills"
if [ -d "$legacy_skills_dir" ]; then
    warning_message="\n\n<important-reminder>IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE YOU MUST TELL THE USER:⚠️ **WARNING:** Conclave now uses Claude Code's skills system. Custom skills in ~/.config/conclave/skills will not be read. Move custom skills to ~/.claude/skills instead. To make this message go away, remove ~/.config/conclave/skills</important-reminder>"
fi

# Check binary version matches plugin.json
version_warning=""
plugin_version=$(grep '"version"' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/.*"version": *"//;s/".*//')
if [ -x "${PLUGIN_ROOT}/conclave" ] && [ -n "$plugin_version" ]; then
    binary_version=$("${PLUGIN_ROOT}/conclave" version 2>/dev/null || echo "unknown")
    if [ "$binary_version" != "dev" ] && [ "$binary_version" != "$plugin_version" ]; then
        version_warning="\n\n<important-reminder>IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE YOU MUST TELL THE USER:⚠️ **WARNING:** Conclave binary version (${binary_version}) does not match plugin version (${plugin_version}). Run \`make build\` in the conclave directory to rebuild, or download the latest release.</important-reminder>"
    fi
fi

# Read using-conclave content
using_conclave_content=$(cat "${PLUGIN_ROOT}/skills/using-conclave/SKILL.md" 2>&1 || echo "Error reading using-conclave skill")

# Escape outputs for JSON using pure bash
escape_for_json() {
    local input="$1"
    local output=""
    local i char
    for (( i=0; i<${#input}; i++ )); do
        char="${input:$i:1}"
        case "$char" in
            $'\\') output+='\\' ;;
            '"') output+='\"' ;;
            $'\n') output+='\n' ;;
            $'\r') output+='\r' ;;
            $'\t') output+='\t' ;;
            *) output+="$char" ;;
        esac
    done
    printf '%s' "$output"
}

using_conclave_escaped=$(escape_for_json "$using_conclave_content")
warning_escaped=$(escape_for_json "$warning_message")
version_warning_escaped=$(escape_for_json "$version_warning")

# Output context injection as JSON
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<EXTREMELY_IMPORTANT>\nYou have conclave.\n\n**The conclave CLI binary is at: \`${PLUGIN_ROOT}/conclave\`** — always use this full path when running conclave commands.\n\n**Below is the full content of your 'conclave:using-conclave' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_conclave_escaped}\n\n${warning_escaped}${version_warning_escaped}\n</EXTREMELY_IMPORTANT>"
  }
}
EOF

exit 0
