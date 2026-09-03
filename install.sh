#!/usr/bin/env bash
# Installs file-guard.sh into ~/.claude/hooks/ and registers the PreToolUse hook.
# Idempotent: safe to run multiple times.

set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
HOOK_DEST="$HOOKS_DIR/file-guard.sh"

SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"

# Resolve jq
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not found. Install jq and retry." >&2
  exit 1
fi

# Install hook script
mkdir -p "$HOOKS_DIR"

# When piped via curl, BASH_SOURCE[0] is empty or "/dev/stdin" — download directly.
_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_src" || "$_src" == "/dev/stdin" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/95pctai/claude-code-big-file-guard-plugin/main/file-guard.sh" \
    -o "$HOOK_DEST"
else
  REPO_ROOT="$(cd "$(dirname "$_src")" && pwd)"
  cp "$REPO_ROOT/file-guard.sh" "$HOOK_DEST"
fi
chmod +x "$HOOK_DEST"

# Merge hook entry into settings.json
HOOK_ENTRY=$(jq -n \
  --arg cmd "$HOOK_DEST" \
  '{"type":"command","command":$cmd}')

MATCHER_ENTRY=$(jq -n \
  --argjson hook "$HOOK_ENTRY" \
  '{"matcher":"Read","hooks":[$hook]}')

if [[ -f "$SETTINGS_FILE" ]]; then
  existing=$(cat "$SETTINGS_FILE")
  existing="${existing:-{}}"
else
  existing='{}'
  mkdir -p "$(dirname "$SETTINGS_FILE")"
fi

# Check whether this exact command is already registered to avoid duplicates
already_registered=$(printf '%s' "$existing" | jq -r \
  --arg cmd "$HOOK_DEST" \
  '[.hooks.PreToolUse[]?.hooks[]? | select(.command == $cmd)] | length' 2>/dev/null || echo 0)

if [[ "$already_registered" -gt 0 ]]; then
  echo "file-guard hook already registered in $SETTINGS_FILE — no changes needed."
else
  updated=$(printf '%s' "$existing" | jq \
    --argjson entry "$MATCHER_ENTRY" \
    '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$entry])')
  printf '%s\n' "$updated" > "$SETTINGS_FILE"
  echo "Hook entry added to $SETTINGS_FILE."
fi

echo ""
echo "file-guard installed successfully."
echo "  Hook script : $HOOK_DEST"
echo "  Settings    : $SETTINGS_FILE"
echo ""
echo "Threshold defaults (override with env vars):"
echo "  FILEGUARD_WARN_BYTES  = 102400  (100 KB — warn)"
echo "  FILEGUARD_BLOCK_BYTES = 1048576 (1 MB  — block)"
