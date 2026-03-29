#!/usr/bin/env bash
# install-mcp.sh — Reinstall MCP servers on a new/fresh machine
#
# This script is a fallback for when ~/.claude.json sync causes issues.
# Run it to declaratively set up your MCP servers from scratch.
#
# Edit the SERVERS array below to match your setup.

set -euo pipefail

info() { echo -e "\033[0;32m[MCP]\033[0m $1"; }

# ─── Define your MCP servers here ────────────────────────────────────
# Format: claude mcp add <name> [--scope user] -- <command> <args...>
#
# These are examples — replace with your actual servers.

info "Adding MCP servers..."

# Linear (project management)
claude mcp add linear --scope user -- npx -y @anthropic/mcp-linear

# Filesystem access
claude mcp add filesystem --scope user -- npx -y @modelcontextprotocol/server-filesystem "$HOME/Documents" "$HOME/Projects"

# GitHub
claude mcp add github --scope user -- npx -y @anthropic/mcp-github

# Context7 (up-to-date library docs)
claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest

# ─── Verify ──────────────────────────────────────────────────────────
info "Installed MCP servers. Current config:"
cat ~/.claude.json | python3 -m json.tool 2>/dev/null || cat ~/.claude.json

echo ""
info "Done. Restart Claude Code to pick up changes."
