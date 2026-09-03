# claude-code-big-file-guard-plugin

A Claude Code `PreToolUse` hook that intercepts `Read` tool calls and guards against large files blowing the context window. Before Claude reads a file, the hook checks its size and either adds a warning (encouraging use of `offset`/`limit`) or hard-blocks the read entirely — keeping expensive context slots free for work that matters.

## Requirements

- **bash** (≥ 4)
- **jq** (1.6+)
- **stat** (standard on Linux and macOS)
- **Claude Code** ≥ 1.x

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/95pctai/claude-code-big-file-guard-plugin/main/install.sh | bash
```

The installer:
1. Downloads `file-guard.sh` to `~/.claude/hooks/file-guard.sh`
2. Merges the `PreToolUse` hook entry into `~/.claude/settings.json` (creates the file if absent)
3. Prints a confirmation with the installed path and threshold defaults

Running it again is safe — it detects an existing registration and skips the merge.

## Manual install

1. Copy `file-guard.sh` somewhere permanent, e.g. `~/.claude/hooks/file-guard.sh`, and make it executable:
   ```bash
   cp file-guard.sh ~/.claude/hooks/file-guard.sh
   chmod +x ~/.claude/hooks/file-guard.sh
   ```
2. Register the hook in `~/.claude/settings.json`. See `settings.json.example` for the snippet:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Read",
           "hooks": [
             {
               "type": "command",
               "command": "/home/<you>/.claude/hooks/file-guard.sh"
             }
           ]
         }
       ]
     }
   }
   ```

## Configuration

Override thresholds with environment variables (set them in your shell profile or pass them in the hook `command`):

| Variable | Default | Meaning |
|---|---|---|
| `FILEGUARD_WARN_BYTES` | `102400` (100 KB) | Files at or above this size trigger a warning asking Claude to use `offset`/`limit`. |
| `FILEGUARD_BLOCK_BYTES` | `1048576` (1 MB) | Files at or above this size are hard-blocked; Claude sees a `deny` decision. |

**Examples:**

```bash
# Warn at 50 KB, block at 512 KB
export FILEGUARD_WARN_BYTES=51200
export FILEGUARD_BLOCK_BYTES=524288

# Disable the warn tier (only block)
export FILEGUARD_WARN_BYTES=1048576
```

To pass env vars through Claude Code's hook runner, wrap the command:

```json
{
  "type": "command",
  "command": "FILEGUARD_WARN_BYTES=51200 ~/.claude/hooks/file-guard.sh"
}
```

## How it works

The hook receives the `Read` tool call as JSON on stdin and checks the target file's size with `stat` (Linux and macOS both supported). It applies a two-threshold design:

- **Warn tier** (`FILEGUARD_WARN_BYTES` ≤ size < `FILEGUARD_BLOCK_BYTES`): outputs `{"additionalContext": "..."}` so Claude sees a warning in its context. The read still proceeds; Claude is nudged to use `offset` and `limit` parameters instead.
- **Block tier** (size ≥ `FILEGUARD_BLOCK_BYTES`): outputs `{"permissionDecision": "deny", "permissionDecisionReason": "..."}` and exits 2. Claude Code treats this as a hard block and the `Read` call is cancelled.
- **Pass-through** (size < `FILEGUARD_WARN_BYTES`): exits 0 with no output; the read proceeds normally.

If `stat` fails (missing file, permission error), the hook logs to stderr and exits 0 — it never silently blocks a legitimate read due to its own error.

## Uninstall

1. Remove the hook entry from `~/.claude/settings.json` (delete the `{"matcher":"Read","hooks":[...]}` object from `hooks.PreToolUse`).
2. Delete the script:
   ```bash
   rm ~/.claude/hooks/file-guard.sh
   ```
