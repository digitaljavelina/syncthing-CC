#!/usr/bin/env bash
# bootstrap.sh — Set up real-time Claude Code config sync across Macs
# Uses: Syncthing (real-time P2P sync) + symlinks
#
# WORKFLOW:
#   Mac A (primary):  Install Syncthing → run bootstrap.sh → pair via Syncthing UI
#   Mac B (secondary): Install Syncthing → pair via Syncthing UI → wait for sync → run bootstrap.sh
#
# Syncthing must be installed and running BEFORE pairing. The web UI at
# http://localhost:8384 is where you exchange Device IDs and share folders.
# You do NOT need to run bootstrap.sh before accessing the Syncthing UI.
#
# Prerequisites: Homebrew installed, Tailscale connected on all machines.

set -euo pipefail

SYNC_DIR="$HOME/Sync/claude-code-config"
CLAUDE_DIR="$HOME/.claude"
BACKUP_SUFFIX="bak.$(date +%s)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Install dependencies ────────────────────────────────────────────
info "Installing dependencies..."
brew install syncthing stow 2>/dev/null || true
brew services start syncthing 2>/dev/null || true

# ─── Create sync directory structure ─────────────────────────────────
info "Creating sync directory structure at $SYNC_DIR"
mkdir -p "$SYNC_DIR/.claude/commands"
mkdir -p "$SYNC_DIR/.claude/hooks"
mkdir -p "$SYNC_DIR/.claude/skills"
mkdir -p "$SYNC_DIR/.claude/agents"
mkdir -p "$SYNC_DIR/.claude/get-shit-done"

# ─── Stow ignore file (machine-specific stuff we never sync) ────────
cat > "$SYNC_DIR/.stow-local-ignore" << 'EOF'
^\.credentials\.json$
^statsig$
^projects$
^settings\.local\.json$
^\.stow-local-ignore$
^\.stignore$
^bootstrap\.sh$
^README\.md$
^install-mcp\.sh$
EOF

# ─── Syncthing ignore file (same exclusions at sync layer) ───────────
cat > "$SYNC_DIR/.stignore" << 'EOF'
// Syncthing ignore patterns for Claude Code config sync
// Machine-specific files — never sync these
.credentials.json
statsig
settings.local.json
// Ignore everything in projects/ except memory folders
// Memory files are small, stable, and valuable across machines
projects/**
!projects/**/memory/
!projects/**/memory/**
// Temp and OS files
.DS_Store
*.swp
*.tmp
EOF

# ─── Migrate existing config into sync dir (first machine only) ──────
if [ -d "$CLAUDE_DIR" ] && [ ! -L "$CLAUDE_DIR" ]; then
    info "Found existing ~/.claude directory. Migrating syncable files..."

    # settings.json
    [ -f "$CLAUDE_DIR/settings.json" ] && \
        cp "$CLAUDE_DIR/settings.json" "$SYNC_DIR/.claude/settings.json"

    # CLAUDE.md (global instructions)
    [ -f "$CLAUDE_DIR/CLAUDE.md" ] && \
        cp "$CLAUDE_DIR/CLAUDE.md" "$SYNC_DIR/.claude/CLAUDE.md"

    # Custom commands
    if [ -d "$CLAUDE_DIR/commands" ] && [ "$(ls -A "$CLAUDE_DIR/commands" 2>/dev/null)" ]; then
        cp -R "$CLAUDE_DIR/commands/"* "$SYNC_DIR/.claude/commands/" 2>/dev/null || true
    fi

    # Hooks (if stored as standalone files in ~/.claude/hooks)
    if [ -d "$CLAUDE_DIR/hooks" ] && [ "$(ls -A "$CLAUDE_DIR/hooks" 2>/dev/null)" ]; then
        cp -R "$CLAUDE_DIR/hooks/"* "$SYNC_DIR/.claude/hooks/" 2>/dev/null || true
    fi

    # Skills (custom skills like tutorial, yt-tutorial, etc.)
    if [ -d "$CLAUDE_DIR/skills" ] && [ "$(ls -A "$CLAUDE_DIR/skills" 2>/dev/null)" ]; then
        cp -R "$CLAUDE_DIR/skills/"* "$SYNC_DIR/.claude/skills/" 2>/dev/null || true
    fi

    # Agents (GSD agent definitions)
    if [ -d "$CLAUDE_DIR/agents" ] && [ "$(ls -A "$CLAUDE_DIR/agents" 2>/dev/null)" ]; then
        cp -R "$CLAUDE_DIR/agents/"* "$SYNC_DIR/.claude/agents/" 2>/dev/null || true
    fi

    # Get Shit Done (GSD templates, workflows, references)
    if [ -d "$CLAUDE_DIR/get-shit-done" ] && [ "$(ls -A "$CLAUDE_DIR/get-shit-done" 2>/dev/null)" ]; then
        cp -R "$CLAUDE_DIR/get-shit-done/"* "$SYNC_DIR/.claude/get-shit-done/" 2>/dev/null || true
    fi

    # Back up the original
    info "Backing up ~/.claude to ~/.claude.$BACKUP_SUFFIX"
    mv "$CLAUDE_DIR" "$CLAUDE_DIR.$BACKUP_SUFFIX"

    # Recreate with machine-local files preserved
    mkdir -p "$CLAUDE_DIR"

    # Restore machine-local files from backup
    BACKUP_DIR="$CLAUDE_DIR.$BACKUP_SUFFIX"
    [ -f "$BACKUP_DIR/.credentials.json" ] && \
        cp "$BACKUP_DIR/.credentials.json" "$CLAUDE_DIR/.credentials.json"
    [ -d "$BACKUP_DIR/statsig" ] && \
        cp -R "$BACKUP_DIR/statsig" "$CLAUDE_DIR/statsig"
    [ -d "$BACKUP_DIR/projects" ] && \
        cp -R "$BACKUP_DIR/projects" "$CLAUDE_DIR/projects"
    [ -f "$BACKUP_DIR/settings.local.json" ] && \
        cp "$BACKUP_DIR/settings.local.json" "$CLAUDE_DIR/settings.local.json"

elif [ -L "$CLAUDE_DIR" ]; then
    warn "~/.claude is already a symlink. Skipping migration."
else
    info "No existing ~/.claude found. Creating fresh sync structure."
fi

# ─── Stow: symlink synced files into ~/.claude ──────────────────────
# Stow expects package_dir/target_structure
# We symlink individual files, not the whole directory, so machine-local
# files (credentials, projects, statsig) coexist with synced symlinks.

info "Creating symlinks via stow-style linking..."

# Link each syncable file individually
for file in settings.json CLAUDE.md; do
    if [ -f "$SYNC_DIR/.claude/$file" ]; then
        # Remove existing file (not symlink) if present
        [ -f "$CLAUDE_DIR/$file" ] && [ ! -L "$CLAUDE_DIR/$file" ] && \
            mv "$CLAUDE_DIR/$file" "$CLAUDE_DIR/$file.$BACKUP_SUFFIX"
        ln -sf "$SYNC_DIR/.claude/$file" "$CLAUDE_DIR/$file"
        info "  Linked $file"
    fi
done

# Link commands directory
if [ -d "$SYNC_DIR/.claude/commands" ]; then
    [ -d "$CLAUDE_DIR/commands" ] && [ ! -L "$CLAUDE_DIR/commands" ] && \
        mv "$CLAUDE_DIR/commands" "$CLAUDE_DIR/commands.$BACKUP_SUFFIX"
    ln -sf "$SYNC_DIR/.claude/commands" "$CLAUDE_DIR/commands"
    info "  Linked commands/"
fi

# Link hooks directory
if [ -d "$SYNC_DIR/.claude/hooks" ]; then
    [ -d "$CLAUDE_DIR/hooks" ] && [ ! -L "$CLAUDE_DIR/hooks" ] && \
        mv "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/hooks.$BACKUP_SUFFIX"
    ln -sf "$SYNC_DIR/.claude/hooks" "$CLAUDE_DIR/hooks"
    info "  Linked hooks/"
fi

# Link skills directory
if [ -d "$SYNC_DIR/.claude/skills" ]; then
    [ -d "$CLAUDE_DIR/skills" ] && [ ! -L "$CLAUDE_DIR/skills" ] && \
        mv "$CLAUDE_DIR/skills" "$CLAUDE_DIR/skills.$BACKUP_SUFFIX"
    ln -sf "$SYNC_DIR/.claude/skills" "$CLAUDE_DIR/skills"
    info "  Linked skills/"
fi

# Link agents directory
if [ -d "$SYNC_DIR/.claude/agents" ]; then
    [ -d "$CLAUDE_DIR/agents" ] && [ ! -L "$CLAUDE_DIR/agents" ] && \
        mv "$CLAUDE_DIR/agents" "$CLAUDE_DIR/agents.$BACKUP_SUFFIX"
    ln -sf "$SYNC_DIR/.claude/agents" "$CLAUDE_DIR/agents"
    info "  Linked agents/"
fi

# Link get-shit-done directory
if [ -d "$SYNC_DIR/.claude/get-shit-done" ]; then
    [ -d "$CLAUDE_DIR/get-shit-done" ] && [ ! -L "$CLAUDE_DIR/get-shit-done" ] && \
        mv "$CLAUDE_DIR/get-shit-done" "$CLAUDE_DIR/get-shit-done.$BACKUP_SUFFIX"
    ln -sf "$SYNC_DIR/.claude/get-shit-done" "$CLAUDE_DIR/get-shit-done"
    info "  Linked get-shit-done/"
fi

# ─── Summary ─────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Claude Code Config Sync — Setup Complete"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Sync directory:  $SYNC_DIR"
echo "  Syncthing UI:    http://localhost:8384"
echo ""
echo "  SYNCED (real-time via Syncthing):"
echo "    ~/.claude/settings.json    → $SYNC_DIR/.claude/settings.json"
echo "    ~/.claude/CLAUDE.md        → $SYNC_DIR/.claude/CLAUDE.md"
echo "    ~/.claude/commands/        → $SYNC_DIR/.claude/commands/"
echo "    ~/.claude/hooks/           → $SYNC_DIR/.claude/hooks/"
echo "    ~/.claude/skills/          → $SYNC_DIR/.claude/skills/"
echo "    ~/.claude/agents/          → $SYNC_DIR/.claude/agents/"
echo "    ~/.claude/get-shit-done/   → $SYNC_DIR/.claude/get-shit-done/"
echo ""
echo "  LOCAL ONLY (not synced):"
echo "    ~/.claude.json             (MCP servers — use install-mcp.sh per machine)"
echo "    ~/.claude/.credentials.json"
echo "    ~/.claude/settings.local.json"
echo "    ~/.claude/statsig/"
echo "    ~/.claude/projects/"
echo ""
echo "  NEXT STEPS:"
echo "    If this is your PRIMARY Mac:"
echo "      1. Open http://localhost:8384"
echo "      2. Add your other Mac as a Remote Device (exchange Device IDs)"
echo "      3. Share the folder: $SYNC_DIR"
echo "      4. On the other Mac: accept the folder share, wait for sync"
echo "      5. On the other Mac: run this same script"
echo ""
echo "    If this is a SECONDARY Mac:"
echo "      You're done! Config is linked and syncing."
echo ""
echo "  TIP: Syncthing works over Tailscale. Set the remote device"
echo "       address to the Tailscale IP (e.g., tcp://100.x.y.z:22000)"
echo "       for reliable connectivity without relay servers."
echo ""
echo "═══════════════════════════════════════════════════════════════"
