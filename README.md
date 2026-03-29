# Claude Code Real-Time Sync Across Multiple Macs

Sync Claude Code configuration (settings, CLAUDE.md, commands, hooks, MCP servers) across multiple Macs in real-time using Syncthing + symlinks.

## Architecture

```
Mac A                              Mac B
~/.claude/                         ~/.claude/
  settings.json    → symlink         settings.json    → symlink
  CLAUDE.md        → symlink         CLAUDE.md        → symlink
  commands/        → symlink         commands/        → symlink
  hooks/           → symlink         hooks/           → symlink
  skills/          → symlink         skills/          → symlink
  agents/          → symlink         agents/          → symlink
  get-shit-done/   → symlink         get-shit-done/   → symlink
  .credentials.json  (local)         .credentials.json  (local)
  settings.local.json (local)        settings.local.json (local)
  projects/          (local)         projects/          (local)
~/.claude.json       (local)       ~/.claude.json       (local)
        ↓                                  ↓
~/Sync/claude-code-config/         ~/Sync/claude-code-config/
        ↕ ── Syncthing (real-time, P2P, over Tailscale) ── ↕
```

### What syncs

| File | Syncs? | Why |
|------|--------|-----|
| `settings.json` | Yes | Permissions, hooks config, allowed tools |
| `CLAUDE.md` | Yes | Global instructions |
| `commands/` | Yes | Custom slash commands |
| `hooks/` | Yes | Hook scripts |
| `skills/` | Yes | Custom skills (tutorial, yt-tutorial, etc.) |
| `agents/` | Yes | GSD agent definitions |
| `get-shit-done/` | Yes | GSD templates, workflows, references |
| `.claude.json` | **No** | MCP servers + OAuth + runtime state — use `install-mcp.sh` per machine |
| `.credentials.json` | No | Auth tokens — machine-specific |
| `settings.local.json` | No | Intentionally local overrides |
| `projects/` | No | Session history — huge, machine-specific |
| `statsig/` | No | Analytics cache |

### Why Syncthing over alternatives

| Option | Problem |
|--------|---------|
| iCloud/Dropbox | Break symlinks, no dotfile support, cloud dependency |
| Git + cron | Not real-time, requires push/pull discipline |
| rsync + cron | One-directional, no conflict handling |
| Syncthing | Bi-directional, real-time, P2P, works over Tailscale, handles conflicts |

## Setup

### 1. Run bootstrap on primary Mac

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

### 2. Configure Syncthing pairing

1. Open http://localhost:8384 on both Macs
2. On Mac A: Actions → Show ID → copy the Device ID
3. On Mac B: Add Remote Device → paste Mac A's Device ID
4. Repeat in reverse (Mac B ID → Mac A)
5. On Mac A: Add Folder → path `~/Sync/claude-code-config` → share with Mac B
6. On Mac B: Accept the incoming folder share

**Tailscale optimization**: Set the remote device address to its Tailscale IP:
```
tcp://100.x.y.z:22000
```
This bypasses relay servers and gives you LAN-speed sync.

### 3. Run bootstrap on secondary Mac(s)

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

The script detects that `~/Sync/claude-code-config` already has files (from Syncthing) and links to them instead of migrating.

## MCP Server Setup (Per Machine)

`~/.claude.json` is not synced. It contains MCP servers, OAuth session, per-project trust state, and runtime caches — all in one file that Claude Code writes to constantly. Syncing it causes conflicts.

Instead, use `install-mcp.sh` to declaratively set up MCP servers on each machine:

```bash
# Edit install-mcp.sh with your servers, then run:
./install-mcp.sh
```

Keep `install-mcp.sh` as your source of truth for which MCP servers you use. When you add a new server, update the script and run it on each Mac.

## Machine-specific overrides

Use `~/.claude/settings.local.json` for machine-specific settings. This file is intentionally excluded from sync.

```json
{
  "env": {
    "GITHUB_TOKEN": "machine-specific-token-here"
  },
  "permissions": {
    "allow": ["Bash(*)"]
  }
}
```

## Syncing Memories Across Machines

The `projects/` directory is excluded from sync because it contains large session history and conversation logs. However, Claude Code's **memory files** (stored in `~/.claude/projects/<project-path>/memory/`) are small, stable, and valuable across machines. If you only use one Mac at a time, these sync cleanly without conflicts.

To sync memories while excluding bulky session data, add a Syncthing `.stignore` pattern:

```
// In the claude-code-config shared folder's .stignore
// Ignore everything in projects/ except memory folders
projects/**
!projects/**/memory/
!projects/**/memory/**
```

Alternatively, add the specific `memory/` paths to `bootstrap.sh` as additional symlink targets.

Note: session history itself is not useful to sync — you cannot resume a session started on a different Mac. Memories, on the other hand, persist context (user preferences, project notes, feedback) that Claude Code reads at the start of every conversation.

## Adding a new Mac

```bash
# 1. Install prerequisites
brew install syncthing stow
# Note: stow is a symlink farm manager that automates creating symlinks
# from a source directory into a target. The bootstrap.sh script handles
# the actual symlinking, so stow is only needed if bootstrap.sh uses it
# internally. Plain `ln -s` commands would achieve the same result.

# 2. Start Syncthing, pair with existing devices
brew services start syncthing
# → pair via http://localhost:8384

# 3. Wait for ~/Sync/claude-code-config to populate

# 4. Run bootstrap
./bootstrap.sh

# 5. (Optional) Set up MCP servers if not syncing .claude.json
./install-mcp.sh
```

## Troubleshooting

**Syncthing conflict files**: Look for `*.sync-conflict-*` in `~/Sync/claude-code-config/`. Merge manually and delete the conflict file.

**Broken symlinks after cleanup**: Re-run `bootstrap.sh`. It's idempotent.

**Claude Code not picking up changes**: Restart Claude Code after config changes. It reads config at startup.

**Syncthing not connecting over Tailscale**: Ensure port 22000 is reachable. Check with `nc -zv 100.x.y.z 22000`.
