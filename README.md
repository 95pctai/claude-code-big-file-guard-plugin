# claude-code-big-file-guard-plugin

![NO GUARD vs WITH GUARD — a bloated robot full of gold coins next to a lean, shielded robot](hero.jpg)

**A 50 MB log file shouldn't cost $30. This Claude Code plugin stops that.**

A single-file plugin that intercepts large `Read` calls before they fill the context window — nudging Claude to be smarter at a first threshold (100 KB by default), and blocking entirely at a second threshold (1 MB by default) until you grant explicit permission.

```bash
curl -fsSL https://raw.githubusercontent.com/95pctai/claude-code-big-file-guard-plugin/main/install.sh | bash
```

---

## The honest picture

Claude is not naive about large files. Given an open-ended task — *"summarize this log"* — it will check sizes with `ls` and `wc`, map structure with `grep`, and extract targeted sections with `sed`. On structured data, it rarely dumps files unprompted.

**The gap:** Give Claude a direct instruction or put it in a context where it decides the full content is necessary — and it will read everything, chunk by chunk, burning tokens one page at a time. In our tests, Opus 5 without this plugin calculated a density map, declared *"Reading it all in 31 sized chunks,"* and consumed ≈ 400K tokens from a 1.6 MB file. The plugin stopped that and required permission first.

This plugin doesn't pretend Claude is reckless. It adds a hard backstop for the cases where Claude's own judgment — or an explicit user instruction — would otherwise lead to an expensive full read.

---

## How it works

Claude Code's `PreToolUse` hook fires before any tool executes. This plugin registers one hook for the `Read` tool. Before the file content reaches Claude's context, the hook checks the file size and makes a decision:

```
Claude ──[PreToolUse]──▶ file-guard.sh ──▶ file.md (1.6 MB)
                              │
                    ┌─────────┴──────────┐
                 100 KB–1 MB          ≥ 1 MB
                 additionalContext     permissionDecision: deny
                 warning injected      Read blocked entirely
                 (read still allowed)  (explicit permission required)
```

The hook exits `0` for small files (zero overhead), emits `additionalContext` JSON for medium files (Claude receives guidance but can still read), and exits `2` with `permissionDecision: deny` for large files — a hard block that Claude cannot proceed past without your explicit consent.

**Bash bypass is intentional.** The hook only guards the `Read` tool. Bash commands (`head`, `grep`, `wc`, `sed`) pass through — these are the aggregation tools Claude should use instead. If you need a true hard firewall against any file access, use Claude Code's `/permissions` to deny reads on a specific path or directory.

---

## Two levels, two behaviors

| File size | What happens |
|-----------|-------------|
| < 100 KB | ✅ Silent pass — no overhead, no friction |
| 100 KB – 1 MB | ⚠️ **T1 · Warning** — Claude receives a token-cost estimate and is invited to use `offset`/`limit`, `head`/`tail`, or `grep` before reading in full. On autonomous tasks, this is usually enough to change strategy. |
| ≥ 1 MB | 🛑 **T2 · Block** — `Read` is denied. Claude is told the file size, the estimated token cost, and instructed to ask you for explicit permission. No workaround — no chunking, no sub-agents — until you say yes. |

Both thresholds are overridable per-session with environment variables. See [Configuration](#configuration).

---

## Evidence: same prompt, same model, different outcome

Test file: `several_papers.md` — 1.6 MB of concatenated academic papers. Not structured; not grep-friendly. Tested with Claude Opus 5.

**With plugin:**

```
> "Read several_papers.md"

● Bash(ls -la && wc -l -c several_papers.md)
  11932 1590592 several_papers.md

● Read(several_papers.md · lines 1–1500)
  Error: file-guard: BLOCKED — several_papers.md is 1590592 bytes
  (≥ 1048576 block threshold)

  several_papers.md is blocked by your file-guard hook (~400K tokens).
  How do you want to proceed?

  1. Targeted sections only
  2. One document at a time
  3. Summarize from abstracts and conclusions
  4. Read everything (grant explicit permission)
```

**Without plugin:**

```
> "Read several_papers.md"

● Read(several_papers.md)
  Error: File content (1.5MB) exceeds maximum allowed size (256KB).
  [Claude treats this as a technical limit, not a permission check — continues]

● Bash(awk 'NR%400==1{...}' several_papers.md)
  1–400: 56KB   401–800: 52KB   801–1200: 52KB   ...
  Total ~1.55MB. Reading it all in 31 sized chunks.

● Read(several_papers.md · lines 1–400)
● Read(several_papers.md · lines 401–800)
● Read(several_papers.md · lines 801–1200)
  ... [28 more chunks] ... ≈ 400K tokens consumed
```

Without the plugin, Claude Code's own 256 KB limit fires — but Claude treats it as a technical obstacle and works around it by chunking. The plugin fires at 1 MB and frames it as a permission decision rather than a size constraint.

---

## Requirements

- **bash** ≥ 4
- **jq** 1.6+
- **stat** (standard on Linux and macOS)
- **Claude Code** ≥ 1.x

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/95pctai/claude-code-big-file-guard-plugin/main/install.sh | bash
```

The installer places `file-guard.sh` at `~/.claude/hooks/file-guard.sh` and merges the `PreToolUse` hook entry into `~/.claude/settings.json`.

### Manual install

```bash
curl -fsSL https://raw.githubusercontent.com/95pctai/claude-code-big-file-guard-plugin/main/file-guard.sh \
  -o ~/.claude/hooks/file-guard.sh
chmod +x ~/.claude/hooks/file-guard.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/file-guard.sh" }]
      }
    ]
  }
}
```

---

## Configuration

Both thresholds are overridable per-session. No config file — just set the variable before launching Claude.

| Variable | Default | Effect |
|----------|---------|--------|
| `FILEGUARD_WARN_BYTES` | `102400` | Files at or above this size receive a token-cost warning. Default is 100 KB (≈ 25K tokens). |
| `FILEGUARD_BLOCK_BYTES` | `1048576` | Files at or above this size are hard-blocked. Default is 1 MB (≈ 262K tokens). |

**Raise the limit for one session:**

```bash
FILEGUARD_BLOCK_BYTES=5242880 claude   # allow up to 5 MB
```

**Disable for one session:**

```bash
FILEGUARD_WARN_BYTES=999999999 FILEGUARD_BLOCK_BYTES=999999999 claude
```

---

## Uninstall

```bash
rm ~/.claude/hooks/file-guard.sh
```

Then edit `~/.claude/settings.json` and remove the `PreToolUse` block (or just the `Read` matcher entry if you have other hooks).

---

## License

MIT
