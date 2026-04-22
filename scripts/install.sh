#!/usr/bin/env bash
# install.sh — Deploy MCP-Toolkit to detected AI agents
set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$TOOLKIT_DIR/scripts"
OUT_DIR="$TOOLKIT_DIR/integrations"
MCP_DIR="$TOOLKIT_DIR/mcp"
AGENTS_DIR="$TOOLKIT_DIR/agents"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[info]${NC}  $*"; }
success() { echo -e "${GREEN}[ok]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Dependency checks ──────────────────────────────────────────────────────────

check_deps() {
  local missing=()

  if ! command -v node &>/dev/null; then
    missing+=("Node.js (https://nodejs.org)")
  fi

  if ! command -v python3 &>/dev/null; then
    missing+=("Python 3 (https://python.org)")
  fi

  if ! command -v uv &>/dev/null; then
    warn "uv not found — git/fetch/time MCP servers won't work"
    warn "Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
    warn "Windows: powershell -c \"irm https://astral.sh/uv/install.ps1 | iex\""
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required dependencies:"
    for dep in "${missing[@]}"; do
      error "  - $dep"
    done
    exit 1
  fi
}

# ── Detect installed agents ────────────────────────────────────────────────────

detect_agents() {
  DETECTED_AGENTS=()

  if command -v claude &>/dev/null || [[ -d "$HOME/.claude" ]]; then
    DETECTED_AGENTS+=("claude-code")
  fi

  if command -v codex &>/dev/null || [[ -f "$HOME/.codex/config.toml" ]]; then
    DETECTED_AGENTS+=("codex")
  fi

  if command -v hermes &>/dev/null || [[ -d "$HOME/.hermes" ]]; then
    DETECTED_AGENTS+=("hermes")
  fi

  if command -v openclaw &>/dev/null || [[ -d "$HOME/.openclaw" ]]; then
    DETECTED_AGENTS+=("openclaw")
  fi
}

# ── Preset selection ────────────────────────────────────────────────────────────

choose_preset() {
  echo ""
  echo "Select a preset:"
  echo ""
  echo "  1) minimal   — No API keys needed."
  echo "              8 servers: filesystem, git, memory, sequential-thinking,"
  echo "              fetch, time, desktop-commander, context7"
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

  REQUIRED_KEYS=()
  while IFS= read -r line; do REQUIRED_KEYS+=("$line"); done < <(python3 -c "
import re
content = open('$PRESET_FILE').read()
m = re.search(r'^required_keys:\s*\[([^\]]*)\]', content, re.MULTILINE)
if m and m.group(1).strip():
    for k in m.group(1).split(','):
        k = k.strip().strip('\"\'')
        if k: print(k)
" 2>/dev/null || true)

  OPTIONAL_KEYS=()
  while IFS= read -r line; do OPTIONAL_KEYS+=("$line"); done < <(python3 -c "
import re
content = open('$PRESET_FILE').read()
m = re.search(r'^optional_keys:\s*\[([^\]]*)\]', content, re.MULTILINE)
if m and m.group(1).strip():
    for k in m.group(1).split(','):
        k = k.strip().strip('\"\'')
        if k: print(k)
" 2>/dev/null || true)

  if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    # shellcheck disable=SC1090
    source "$ENV_FILE" 2>/dev/null || true
    set +o allexport
  fi

  if [[ ${#REQUIRED_KEYS[@]} -gt 0 ]]; then
    echo ""
    info "Required API keys for '$PRESET' preset:"
    for key in "${REQUIRED_KEYS[@]}"; do
      current="${!key:-}"
      if [[ -n "$current" ]]; then
        success "$key already set"
      else
        echo ""
        echo "  $key"
        [[ "$key" == "GITHUB_PERSONAL_ACCESS_TOKEN" ]] && \
          echo "  Get free token: https://github.com/settings/tokens (scopes: repo, read:user)"
        read -rsp "  Enter value (hidden): " value; echo ""
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
    info "Optional API keys (Enter to skip):"
    for key in "${OPTIONAL_KEYS[@]}"; do
      current="${!key:-}"
      if [[ -n "$current" ]]; then
        success "$key already set"
      else
        echo ""
        echo "  $key (optional)"
        case "$key" in
          BRAVE_API_KEY)     echo "  Free tier: https://brave.com/search/api/" ;;
          FIRECRAWL_API_KEY) echo "  Free tier: https://www.firecrawl.dev" ;;
        esac
        read -rsp "  Enter value or Enter to skip: " value; echo ""
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

# ── Install to Claude Code ─────────────────────────────────────────────────────

install_claude() {
  info "Installing to Claude Code..."
  local claude_dir="$HOME/.claude"
  local mcp_src="$OUT_DIR/claude-code/mcp-config.json"

  # MCP config path (Claude Code CLI uses ~/.claude.json, not Desktop config)
  local mcp_dst="$HOME/.claude.json"

  # Skills
  mkdir -p "$claude_dir/skills"
  for skill_dir in "$OUT_DIR/claude-code/skills"/*/; do
    local skill_name; skill_name="$(basename "$skill_dir")"
    mkdir -p "$claude_dir/skills/$skill_name"
    cp "$skill_dir/skill.md" "$claude_dir/skills/$skill_name/skill.md"
  done
  success "Skills → $claude_dir/skills/"

  # Agent personas
  mkdir -p "$claude_dir/agents"
  find "$AGENTS_DIR" -name "*.md" \
    ! -path "*/integrations/*" ! -path "*README*" \
    ! -path "*CONTRIBUTING*" ! -path "*SECURITY*" \
    ! -path "*/strategy/*" ! -path "*/examples/*" \
    ! -path "*/scripts/*" | while read -r f; do
    cp "$f" "$claude_dir/agents/$(basename "$f")"
  done
  local agent_count; agent_count=$(ls "$claude_dir/agents/" | wc -l | tr -d ' ')
  success "Agents ($agent_count personas) → $claude_dir/agents/"

  # MCP config — merge into ~/.claude.json
  if [[ -f "$mcp_dst" ]]; then
    python3 - <<PYEOF
import json, os
src = json.load(open("$mcp_src"))
dst = json.load(open("$mcp_dst"))
dst.setdefault("mcpServers", {})
added = [k for k in src["mcpServers"] if k not in dst["mcpServers"]]
dst["mcpServers"].update(src["mcpServers"])
with open("$mcp_dst", "w") as f:
    json.dump(dst, f, indent=2)
print(f"  Added servers: {', '.join(added) if added else 'none (already present)'}")
PYEOF
    success "MCP config merged → $mcp_dst"
  else
    warn "$mcp_dst not found — skipping MCP config (run Claude Code once first)"
  fi

  warn "Restart Claude Code to activate new MCP servers"
}

# ── Install to Codex ───────────────────────────────────────────────────────────

install_codex() {
  info "Installing to Codex..."
  local codex_dir="$HOME/.codex"
  local config_dst="$codex_dir/config.toml"
  local mcp_src="$OUT_DIR/codex/mcp-config.toml"

  if [[ ! -d "$codex_dir" ]]; then
    warn "~/.codex not found — skipping Codex install"
    return
  fi

  # Skills
  mkdir -p "$codex_dir/skills"
  for skill_dir in "$OUT_DIR/codex/skills"/*/; do
    local skill_name; skill_name="$(basename "$skill_dir")"
    mkdir -p "$codex_dir/skills/$skill_name"
    cp "$skill_dir/skill.md" "$codex_dir/skills/$skill_name/skill.md"
  done
  success "Skills → $codex_dir/skills/"

  # Agent personas → rules
  mkdir -p "$codex_dir/rules"
  local agent_count=0
  find "$AGENTS_DIR" -name "*.md" \
    ! -path "*/integrations/*" ! -path "*README*" \
    ! -path "*CONTRIBUTING*" ! -path "*SECURITY*" \
    ! -path "*/strategy/*" ! -path "*/examples/*" \
    ! -path "*/scripts/*" | while read -r f; do
    cp "$f" "$codex_dir/rules/agency-$(basename "$f")"
  done
  agent_count=$(ls "$codex_dir/rules/" | grep "^agency-" | wc -l | tr -d ' ')
  success "Agents ($agent_count personas) → $codex_dir/rules/"

  # MCP config — merge into config.toml
  if [[ -f "$config_dst" ]]; then
    python3 - <<PYEOF
import re, os

new_blocks = open("$mcp_src").read()
existing = open("$config_dst").read()

# Parse new server names from generated toml
new_servers = re.findall(r'^\[mcp_servers\.([^\]\.]+)\]', new_blocks, re.MULTILINE)
added = []

for server in new_servers:
    if f"[mcp_servers.{server}]" not in existing:
        # Extract this server's block from new_blocks
        pattern = rf'(\[mcp_servers\.{re.escape(server)}\][^\[]*(?:\[mcp_servers\.{re.escape(server)}\.env\][^\[]*)?)'
        m = re.search(pattern, new_blocks, re.DOTALL)
        if m:
            block = m.group(1).strip()
            # Insert before END marker if present, else append
            if "# END OMC MANAGED MCP REGISTRY" in existing:
                existing = existing.replace(
                    "# END OMC MANAGED MCP REGISTRY",
                    block + "\n\n# END OMC MANAGED MCP REGISTRY"
                )
            else:
                existing += "\n" + block + "\n"
            added.append(server)

with open("$config_dst", "w") as f:
    f.write(existing)
print(f"  Added servers: {', '.join(added) if added else 'none (already present)'}")
PYEOF
    success "MCP config merged → $config_dst"
  else
    cp "$mcp_src" "$config_dst"
    success "MCP config written → $config_dst"
  fi

  warn "Restart Codex to activate new MCP servers"
}

# ── Install to Hermes ──────────────────────────────────────────────────────────

install_hermes() {
  info "Installing to Hermes..."
  local hermes_dir="$HOME/.hermes"

  mkdir -p "$hermes_dir/skills"
  for category_dir in "$OUT_DIR/hermes/skills"/*/; do
    local category; category="$(basename "$category_dir")"
    mkdir -p "$hermes_dir/skills/$category"
    cp -r "$category_dir"/* "$hermes_dir/skills/$category/" 2>/dev/null || true
  done
  success "Skills → $hermes_dir/skills/"

  cp "$OUT_DIR/hermes/mcp-config.yaml" "$hermes_dir/mcp-config.yaml"
  success "MCP config → $hermes_dir/mcp-config.yaml"

  warn "Run 'hermes reload' to activate"
}

# ── Install to OpenClaw ────────────────────────────────────────────────────────

install_openclaw() {
  info "Installing to OpenClaw..."
  local openclaw_dir="$HOME/.openclaw/workspace/skills"

  mkdir -p "$openclaw_dir"
  for skill_dir in "$OUT_DIR/openclaw/skills"/*/; do
    local skill_name; skill_name="$(basename "$skill_dir")"
    mkdir -p "$openclaw_dir/$skill_name"
    cp "$skill_dir/SKILL.md" "$openclaw_dir/$skill_name/SKILL.md"
  done
  success "Skills → $openclaw_dir"
  info "Note: OpenClaw uses its own plugin system for MCP servers."
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  MCP-Toolkit Installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  check_deps
  detect_agents

  if [[ ${#DETECTED_AGENTS[@]} -eq 0 ]]; then
    warn "No AI agents detected."
    info "  Claude Code: https://claude.ai/code"
    info "  Codex:       npm install -g @openai/codex"
    info "  Hermes:      https://hermes.ai"
    info "  OpenClaw:    https://openclaw.ai"
    echo ""
    read -rp "Continue anyway? [y/N]: " cont
    [[ "${cont:-n}" =~ ^[yY] ]] || exit 0
    DETECTED_AGENTS=("claude-code")
  else
    info "Detected: ${DETECTED_AGENTS[*]}"
  fi

  choose_preset
  collect_keys

  info "Generating integration files..."
  bash "$SCRIPTS_DIR/convert.sh" "$PRESET"

  echo ""
  info "Installing to agents..."
  for agent in "${DETECTED_AGENTS[@]}"; do
    case "$agent" in
      claude-code) install_claude ;;
      codex)       install_codex ;;
      hermes)      install_hermes ;;
      openclaw)    install_openclaw ;;
    esac
  done

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  ${GREEN}Done!${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  info "Installed to: ${DETECTED_AGENTS[*]}"
  info "Skills: autopilot, ralph, ultrawork, team, ultraqa, deep-dive,"
  info "        trace, wiki, scientific-writing, review, security-review"
  info "Agents: 205 expert personas in ~/.claude/agents/ (and ~/.codex/rules/)"
  echo ""
}

main "$@"
