# Claude Code Real-Time Sync Across Multiple Macs

Sync Claude Code configuration (settings, CLAUDE.md, commands, hooks, MCP servers) across multiple Macs in real-time using Syncthing + symlinks.

## What syncs

| File | Syncs? | Why |
|------|--------|-----|
| `settings.json` | Yes | Permissions, hooks config, allowed tools |
| `CLAUDE.md` | Yes | Global instructions |
| `commands/` | Yes | Custom slash commands |
| `hooks/` | Yes | Hook scripts |
| `skills/` | Yes | Custom skills |
| `agents/` | Yes | Agent definitions |
| Any custom dirs | Yes | Add to `bootstrap.sh` as needed |
| `.claude.json` | **No** | MCP servers + OAuth + runtime state — use `install-mcp.sh` per machine |
| `.credentials.json` | No | Auth tokens — machine-specific |
| `settings.local.json` | No | Intentionally local overrides |
| `projects/` | No | Session history — huge, machine-specific |
| `statsig/` | No | Analytics cache |

## Why Syncthing over alternatives

| Option | Problem |
|--------|---------|
| iCloud/Dropbox | Break symlinks, no dotfile support, cloud dependency |
| Git + cron | Not real-time, requires push/pull discipline |
| rsync + cron | One-directional, no conflict handling |
| Syncthing | Bi-directional, real-time, P2P, works over Tailscale, handles conflicts |

## Setup

### 1. Install Syncthing on ALL Macs first

Before running `bootstrap.sh` on any machine, install and start Syncthing on every Mac that will participate in sync:

```bash
brew install syncthing
brew services start syncthing
```

Verify it's running by opening http://localhost:8384 — this is Syncthing's local web UI. Each Mac runs its own instance.

### 2. Run bootstrap on primary Mac (Mac A)

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

This migrates your existing `~/.claude` config into `~/Sync/claude-code-config` and creates symlinks back.

### 3. Pair the Macs via Syncthing

1. Open http://localhost:8384 on both Macs (hard refresh if the UI seems unresponsive)
2. On Mac A: Actions → Show ID → copy the Device ID
3. On Mac B: Add Remote Device → paste Mac A's Device ID
4. Repeat in reverse (Mac B ID → Mac A)
5. Wait for both devices to show **"Connected"** (green) under Remote Devices before sharing folders
6. On Mac A: Add Folder → path `~/Sync/claude-code-config` → share with Mac B
7. On Mac B: Accept the incoming folder share — **check these critical settings:**
   - **Folder Path**: `~/Sync/claude-code-config`
   - **Folder Type** (Advanced tab): Must be **"Send & Receive"** — NOT "Receive Encrypted" (the default in some cases). "Receive Encrypted" will sync garbled `.syncthing-enc` files instead of your actual config.
   - **Encryption password**: Must be **empty** on both sides. If Mac A has an encryption password set for Mac B under the folder's Sharing tab, clear it.
8. Wait for the folder to finish syncing (Syncthing UI shows "Up to Date" on both Macs)

**Tailscale optimization**: Set the remote device address to its Tailscale IP:
```
tcp://100.x.y.z:22000
```
This bypasses relay servers and gives you LAN-speed sync.

### 4. Run bootstrap on secondary Mac(s)

**Wait until sync is fully complete** (both Macs show "Up to Date") before running this:

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

The script detects that `~/Sync/claude-code-config` already has files (from Syncthing) and creates symlinks to them instead of migrating. If you ran it too early, just re-run it after sync completes — it's idempotent.

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
# 1. Install and start Syncthing
brew install syncthing
brew services start syncthing

# 2. Open http://localhost:8384 and pair with existing devices
#    - Exchange Device IDs with an existing Mac
#    - Accept the claude-code-config folder share
#    - IMPORTANT: Set Folder Type to "Send & Receive" (not "Receive Encrypted")
#    - IMPORTANT: Leave the encryption password empty
#    - Wait for sync to complete (UI shows "Up to Date")

# 3. Run bootstrap (creates symlinks to the synced config)
./bootstrap.sh

# 4. (Optional) Set up MCP servers
./install-mcp.sh
```

## Troubleshooting

**Syncthing UI unresponsive or buttons not working**: Hard refresh with `Cmd+Shift+R` or try a different browser. The single-page app can get stuck.

**"Receive Encrypted" / `.syncthing-enc` files**: You accepted the folder with the wrong type. Remove the folder in Syncthing (this doesn't delete files on disk), delete any `.syncthing-enc` directories from `~/Sync/claude-code-config/`, then re-accept the folder share with Folder Type set to "Send & Receive" and no encryption password.

**"Remote expects to exchange encrypted data"**: Mac A has an encryption password set for the remote device on this folder. On Mac A: click the folder → Edit → Sharing tab → find the remote device → clear the encryption password field → Save. Then restart Syncthing on both Macs: `brew services restart syncthing`.

**Devices stuck on "Disconnected"**: Restart Syncthing on both Macs: `brew services restart syncthing`. Give it 30 seconds to reconnect.

**Duplicate folders syncing the same path**: If you see two folder IDs both pointing to `~/Sync/claude-code-config`, remove the extra one. Only one folder ID should manage each path.

**macOS permissions blocking sync**: Grant Syncthing Full Disk Access in System Settings → Privacy & Security → Full Disk Access. The binary is usually at `/opt/homebrew/bin/syncthing`. Restart after: `brew services restart syncthing`.

**Syncthing conflict files**: Look for `*.sync-conflict-*` in `~/Sync/claude-code-config/`. Merge manually and delete the conflict file.

**Broken symlinks after cleanup**: Re-run `bootstrap.sh`. It's idempotent.

**Claude Code not picking up changes**: Restart Claude Code after config changes. It reads config at startup.

**Syncthing not connecting over Tailscale**: Ensure port 22000 is reachable. Check with `nc -zv 100.x.y.z 22000`.
