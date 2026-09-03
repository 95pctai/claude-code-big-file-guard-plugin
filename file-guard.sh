#!/usr/bin/env bash
# Claude Code PreToolUse hook — guards large file reads from blowing context window.
# Reads JSON from stdin, checks file size, warns or blocks based on thresholds.

set -euo pipefail

WARN_BYTES="${FILEGUARD_WARN_BYTES:-102400}"
BLOCK_BYTES="${FILEGUARD_BLOCK_BYTES:-1048576}"

input=$(cat)

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -z "$file_path" ]]; then
  exit 0
fi

# Support Linux (stat -c%s) and macOS (stat -f%z)
if size=$(stat -c%s "$file_path" 2>/dev/null); then
  : # Linux succeeded
elif size=$(stat -f%z "$file_path" 2>/dev/null); then
  : # macOS succeeded
else
  # File unreadable or stat unavailable — pass through silently
  echo "file-guard: could not stat '$file_path'" >&2
  exit 0
fi

if (( size >= BLOCK_BYTES )); then
  printf '{"permissionDecision":"deny","permissionDecisionReason":"%s is %d bytes (≥%d bytes block threshold). Read blocked to protect context window. Lower FILEGUARD_BLOCK_BYTES to change this threshold."}\n' \
    "$file_path" "$size" "$BLOCK_BYTES"
  exit 2
elif (( size >= WARN_BYTES )); then
  tokens=$(( size / 4 / 1000 ))
  printf '{"additionalContext":"Warning: %s is %d bytes (≈%dK tokens). This is a large file — consider reading only the lines you need with the offset/limit parameters."}\n' \
    "$file_path" "$size" "$tokens"
  exit 0
fi

exit 0
