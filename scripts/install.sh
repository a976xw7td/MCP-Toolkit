#!/usr/bin/env bash
# install.sh — Deploy MCP-Toolkit to detected AI agents
set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$TOOLKIT_DIR/scripts"
OUT_DIR="$TOOLKIT_DIR/integrations"
MCP_DIR="$TOOLKIT_DIR/mcp"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[info]${NC}  $*"; }
success() { echo -e "${GREEN}[ok]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Detect installed agents ────────────────────────────────────────────────────

detect_agents() {
  DETECTED_AGENTS=()

  # Claude Code
  if command -v claude &>/dev/null || [[ -d "$HOME/.claude" ]]; then
    DETECTED_AGENTS+=("claude-code")
  fi

  # Hermes
  if command -v hermes &>/dev/null || [[ -d "$HOME/.hermes" ]]; then
    DETECTED_AGENTS+=("hermes")
  fi

  # OpenClaw
  if command -v openclaw &>/dev/null || [[ -d "$HOME/.openclaw" ]]; then
    DETECTED_AGENTS+=("openclaw")
  fi
}

# ── Preset selection ────────────────────────────────────────────────────────────

choose_preset() {
  echo ""
  echo "Select a preset:"
  echo ""
  echo "  1) minimal   — No API keys needed. Core tools only."
  echo "              8 servers: filesystem, git, memory, reasoning, fetch, time,"
  echo "              desktop-commander, context7"
  echo ""
  echo "  2) developer — Requires a free GitHub Personal Access Token."
  echo "              10 servers: + github, brave-search"
  echo ""
  echo "  3) full      — All features. Requires GitHub PAT."
  echo "              11 servers: + firecrawl (web scraping)"
  echo ""
  read -rp "Enter choice [1-3, default=1]: " choice
  case "${choice:-1}" in
    1) PRESET="minimal" ;;
    2) PRESET="developer" ;;
    3) PRESET="full" ;;
    *) warn "Invalid choice, using minimal"; PRESET="minimal" ;;
  esac
  info "Preset: $PRESET"
}

# ── Collect required API keys ──────────────────────────────────────────────────

collect_keys() {
  PRESET_FILE="$MCP_DIR/presets/${PRESET}.yaml"
  ENV_FILE="$TOOLKIT_DIR/.env"

  # Parse required keys from preset
  mapfile -t REQUIRED_KEYS < <(
    python3 -c "
import re
content = open('$PRESET_FILE').read()
m = re.search(r'^required_keys:\s*\[([^\]]*)\]', content, re.MULTILINE)
if m and m.group(1).strip():
    keys = [k.strip().strip(\"'\\\"\") for k in m.group(1).split(',') if k.strip()]
    for k in keys: print(k)
" 2>/dev/null || true
  )

  mapfile -t OPTIONAL_KEYS < <(
    python3 -c "
import re
content = open('$PRESET_FILE').read()
m = re.search(r'^optional_keys:\s*\[([^\]]*)\]', content, re.MULTILINE)
if m and m.group(1).strip():
    keys = [k.strip().strip(\"'\\\"\") for k in m.group(1).split(',') if k.strip()]
    for k in keys: print(k)
" 2>/dev/null || true
  )

  # Load existing .env if present
  if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    # shellcheck disable=SC1090
    source "$ENV_FILE" 2>/dev/null || true
    set +o allexport
  fi

  echo ""
  if [[ ${#REQUIRED_KEYS[@]} -gt 0 ]]; then
    info "This preset requires the following API keys:"
    for key in "${REQUIRED_KEYS[@]}"; do
      current="${!key:-}"
      if [[ -n "$current" ]]; then
        success "$key already set"
      else
        echo ""
        echo "  $key"
        case "$key" in
          GITHUB_PERSONAL_ACCESS_TOKEN)
            echo "  Get one free at: https://github.com/settings/tokens"
            echo "  Required scopes: repo, read:user"
            ;;
        esac
        read -rsp "  Enter value (input hidden): " value
        echo ""
        if [[ -n "$value" ]]; then
          export "$key"="$value"
          echo "${key}=${value}" >> "$ENV_FILE"
          success "$key saved"
        else
          warn "$key skipped — some features may not work"
        fi
      fi
    done
  fi

  if [[ ${#OPTIONAL_KEYS[@]} -gt 0 ]]; then
    echo ""
    info "Optional API keys (press Enter to skip):"
    for key in "${OPTIONAL_KEYS[@]}"; do
      current="${!key:-}"
      if [[ -n "$current" ]]; then
        success "$key already set (optional)"
      else
        echo ""
        echo "  $key (optional)"
        case "$key" in
          BRAVE_API_KEY)
            echo "  Free tier at: https://brave.com/search/api/"
            ;;
          FIRECRAWL_API_KEY)
            echo "  Free tier at: https://www.firecrawl.dev"
            ;;
        esac
        read -rsp "  Enter value or press Enter to skip: " value
        echo ""
        if [[ -n "$value" ]]; then
          export "$key"="$value"
          echo "${key}=${value}" >> "$ENV_FILE"
          success "$key saved"
        else
          info "$key skipped"
        fi
      fi
    done
  fi
}

# ── Run convert ────────────────────────────────────────────────────────────────

run_convert() {
  info "Generating integration files for preset: $PRESET..."
  bash "$SCRIPTS_DIR/convert.sh" "$PRESET"
}

# ── Install to Claude Code ─────────────────────────────────────────────────────

install_claude() {
  info "Installing to Claude Code..."
  CLAUDE_DIR="$HOME/.claude"
  CLAUDE_SKILLS="$CLAUDE_DIR/skills"
  CLAUDE_MCP_SRC="$OUT_DIR/claude-code/mcp-config.json"
  CLAUDE_MCP_DST="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

  # Skills
  mkdir -p "$CLAUDE_SKILLS"
  for skill_dir in "$OUT_DIR/claude-code/skills"/*/; do
    skill_name="$(basename "$skill_dir")"
    target="$CLAUDE_SKILLS/$skill_name"
    mkdir -p "$target"
    cp "$skill_dir/skill.md" "$target/skill.md"
  done
  success "Skills installed to $CLAUDE_SKILLS"

  # MCP config — merge into existing config or create new
  if [[ -f "$CLAUDE_MCP_DST" ]]; then
    python3 - <<PYEOF
import json, sys, os

src = json.load(open("$CLAUDE_MCP_SRC"))
dst_path = "$CLAUDE_MCP_DST"
dst = json.load(open(dst_path)) if os.path.exists(dst_path) else {}

dst.setdefault("mcpServers", {})
dst["mcpServers"].update(src.get("mcpServers", {}))

with open(dst_path, "w") as f:
    json.dump(dst, f, indent=2)
print(f"  Merged MCP config into {dst_path}")
PYEOF
    success "MCP config merged into $CLAUDE_MCP_DST"
  else
    mkdir -p "$(dirname "$CLAUDE_MCP_DST")"
    cp "$CLAUDE_MCP_SRC" "$CLAUDE_MCP_DST"
    success "MCP config written to $CLAUDE_MCP_DST"
  fi

  warn "Restart Claude Code to activate MCP servers"
}

# ── Install to Hermes ──────────────────────────────────────────────────────────

install_hermes() {
  info "Installing to Hermes..."
  HERMES_DIR="$HOME/.hermes"
  HERMES_SKILLS="$HERMES_DIR/skills"
  HERMES_MCP_SRC="$OUT_DIR/hermes/mcp-config.yaml"
  HERMES_MCP_DST="$HERMES_DIR/mcp-config.yaml"

  mkdir -p "$HERMES_SKILLS"

  # Copy skill category directories
  for category_dir in "$OUT_DIR/hermes/skills"/*/; do
    category="$(basename "$category_dir")"
    mkdir -p "$HERMES_SKILLS/$category"
    cp -r "$category_dir"/* "$HERMES_SKILLS/$category/" 2>/dev/null || true
  done
  success "Skills installed to $HERMES_SKILLS"

  # MCP config
  cp "$HERMES_MCP_SRC" "$HERMES_MCP_DST"
  success "MCP config written to $HERMES_MCP_DST"

  warn "Run 'hermes reload' to activate MCP servers"
}

# ── Install to OpenClaw ────────────────────────────────────────────────────────

install_openclaw() {
  info "Installing to OpenClaw..."
  OPENCLAW_DIR="$HOME/.openclaw"
  OPENCLAW_SKILLS="$OPENCLAW_DIR/workspace/skills"

  mkdir -p "$OPENCLAW_SKILLS"

  for skill_dir in "$OUT_DIR/openclaw/skills"/*/; do
    skill_name="$(basename "$skill_dir")"
    target="$OPENCLAW_SKILLS/$skill_name"
    mkdir -p "$target"
    cp "$skill_dir/SKILL.md" "$target/SKILL.md"
  done
  success "Skills installed to $OPENCLAW_SKILLS"

  info "Note: OpenClaw uses its own plugin system for MCP. See agents/integrations/openclaw/README.md"
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  MCP-Toolkit Installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  detect_agents

  if [[ ${#DETECTED_AGENTS[@]} -eq 0 ]]; then
    warn "No AI agents detected."
    info "Install Claude Code: https://claude.ai/code"
    info "Install Hermes: https://hermes.ai"
    info "Install OpenClaw: https://openclaw.ai"
    echo ""
    read -rp "Continue anyway (manual install)? [y/N]: " cont
    [[ "${cont:-n}" =~ ^[yY] ]] || exit 0
    DETECTED_AGENTS=("claude-code")
  else
    info "Detected agents: ${DETECTED_AGENTS[*]}"
  fi

  choose_preset
  collect_keys
  run_convert

  echo ""
  info "Installing to detected agents..."
  for agent in "${DETECTED_AGENTS[@]}"; do
    case "$agent" in
      claude-code) install_claude ;;
      hermes)      install_hermes ;;
      openclaw)    install_openclaw ;;
    esac
  done

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  ${GREEN}Installation complete!${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  info "What's installed:"
  info "  Skills: autopilot, ralph, ultrawork, team, ultraqa, deep-dive,"
  info "          trace, wiki, scientific-writing, review, security-review"
  info "  MCP servers: $(echo "${SERVERS[*]:-"see preset"}" | tr ' ' ', ')"
  echo ""
  info "205 expert agent personas are in: $TOOLKIT_DIR/agents/"
  info "See the README.md for usage examples."
  echo ""
}

main "$@"
