#!/usr/bin/env bash
# install.sh — Deploy MCP-Toolkit to detected AI agents
# Security-hardened: path sandbox enforcement, input validation, injection prevention
set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$TOOLKIT_DIR/scripts"
OUT_DIR="$TOOLKIT_DIR/integrations"
MCP_DIR="$TOOLKIT_DIR/mcp"
AGENTS_DIR="$TOOLKIT_DIR/agents"
ENV_FILE="$TOOLKIT_DIR/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[info]${NC}  $*"; }
success() { echo -e "${GREEN}[ok]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Security Utilities ─────────────────────────────────────────────────────────

# Strip control characters from user input (prevents embedded newlines, null bytes)
sanitize_input() {
  printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]'
}

# Validate API key: only alphanumeric + _ . - allowed (safe for JSON/TOML embedding)
assert_safe_key() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9_./-]+$ ]]; then
    error "Key '$name' contains characters not allowed in API keys"
    error "Allowed: alphanumeric, underscore, hyphen, period, forward-slash"
    exit 1
  fi
  if (( ${#value} < 8 || ${#value} > 512 )); then
    warn "Key '$name' has unusual length (${#value} chars) — please verify"
  fi
}

# Validate that the sandbox path resolves within $HOME (prevents directory traversal)
validate_sandbox() {
  local raw="$1"
  local canon home_real
  canon="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$raw" 2>/dev/null)" || {
    error "Cannot resolve sandbox path: $raw"
    exit 1
  }
  home_real="$(python3 -c "import os; print(os.path.realpath(os.path.expanduser('~')))")"
  if [[ "$canon" != "$home_real" && "$canon" != "$home_real/"* ]]; then
    error "SECURITY VIOLATION: MCP_FS_SANDBOX must be within \$HOME"
    error "  HOME:     $home_real"
    error "  Resolved: $canon"
    exit 1
  fi
  echo "$canon"
}

# ── Dependency checks ──────────────────────────────────────────────────────────

check_deps() {
  local missing=()
  command -v node    &>/dev/null || missing+=("Node.js 18+  →  https://nodejs.org")
  command -v python3 &>/dev/null || missing+=("Python 3.8+  →  https://python.org")
  if (( ${#missing[@]} > 0 )); then
    error "Missing required dependencies:"
    for dep in "${missing[@]}"; do error "  • $dep"; done
    exit 1
  fi
  command -v uv &>/dev/null || {
    warn "uv not found — git/fetch/time MCP servers will be unavailable"
    warn "Install (Unix):    curl -LsSf https://astral.sh/uv/install.sh | sh"
    warn "Install (Windows): powershell -c \"irm https://astral.sh/uv/install.ps1 | iex\""
  }
}

# ── Detect installed agents ────────────────────────────────────────────────────

detect_agents() {
  DETECTED_AGENTS=()
  { command -v claude   &>/dev/null || [[ -d "$HOME/.claude" ]]; }              && DETECTED_AGENTS+=("claude-code")
  { command -v codex    &>/dev/null || [[ -f "$HOME/.codex/config.toml" ]]; }   && DETECTED_AGENTS+=("codex")
  { command -v hermes   &>/dev/null || [[ -d "$HOME/.hermes" ]]; }              && DETECTED_AGENTS+=("hermes")
  { command -v openclaw &>/dev/null || [[ -d "$HOME/.openclaw" ]]; }            && DETECTED_AGENTS+=("openclaw")
}

# ── Preset selection ────────────────────────────────────────────────────────────

choose_preset() {
  echo ""
  echo "Select a preset:"
  echo ""
  echo "  1) minimal    — No API keys needed. 8 core servers."
  echo "  2) developer  — GitHub PAT required. 10 servers."
  echo "  3) full       — All 11 servers. GitHub PAT required."
  echo ""
  read -rp "Choice [1-3, default=1]: " choice
  case "${choice:-1}" in
    1) PRESET="minimal" ;;
    2) PRESET="developer" ;;
    3) PRESET="full" ;;
    *) warn "Invalid choice, defaulting to minimal"; PRESET="minimal" ;;
  esac
  info "Using preset: $PRESET"
}

# ── Collect & validate API keys ────────────────────────────────────────────────

collect_keys() {
  local preset_file="$MCP_DIR/presets/${PRESET}.yaml"
  local required_keys=() optional_keys=()

  while IFS= read -r line; do required_keys+=("$line"); done < <(python3 -c "
import re
content = open('$preset_file').read()
m = re.search(r'^required_keys:\s*\[([^\]]*)\]', content, re.MULTILINE)
if m and m.group(1).strip():
    for k in m.group(1).split(','):
        k = k.strip().strip('\"\'')
        if k: print(k)
" 2>/dev/null || true)

  while IFS= read -r line; do optional_keys+=("$line"); done < <(python3 -c "
import re
content = open('$preset_file').read()
m = re.search(r'^optional_keys:\s*\[([^\]]*)\]', content, re.MULTILINE)
if m and m.group(1).strip():
    for k in m.group(1).split(','):
        k = k.strip().strip('\"\'')
        if k: print(k)
" 2>/dev/null || true)

  # Load existing .env if present
  if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    # shellcheck disable=SC1090
    source "$ENV_FILE" 2>/dev/null || true
    set +o allexport
  fi

  _prompt_key() {
    local key="$1" required="${2:-false}"
    local current="${!key:-}"
    if [[ -n "$current" ]]; then
      success "$key already set"; return
    fi
    echo ""; echo "  $key$([ "$required" = "true" ] && echo " (required)" || echo " (optional)")"
    case "$key" in
      GITHUB_PERSONAL_ACCESS_TOKEN)
        echo "  Scopes needed: repo, read:user"
        echo "  Create at: https://github.com/settings/tokens" ;;
      BRAVE_API_KEY)     echo "  Free tier: https://brave.com/search/api/" ;;
      FIRECRAWL_API_KEY) echo "  Free tier: https://www.firecrawl.dev" ;;
    esac
    read -rsp "  Enter value (hidden, Enter to skip): " raw_value; echo ""
    [[ -z "$raw_value" ]] && {
      [ "$required" = "true" ] && warn "$key skipped — some features may not work"; return
    }
    local value; value="$(sanitize_input "$raw_value")"
    assert_safe_key "$key" "$value"
    export "$key"="$value"
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    success "$key saved to .env"
  }

  if (( ${#required_keys[@]} > 0 )); then
    echo ""; info "Required keys for '$PRESET' preset:"
    for key in "${required_keys[@]}"; do _prompt_key "$key" "true"; done
  fi
  if (( ${#optional_keys[@]} > 0 )); then
    echo ""; info "Optional keys (Enter to skip):"
    for key in "${optional_keys[@]}"; do _prompt_key "$key" "false"; done
  fi
}

# ── Configure filesystem sandbox ───────────────────────────────────────────────

configure_sandbox() {
  [[ -f "$ENV_FILE" ]] && {
    # shellcheck disable=SC1090
    source "$ENV_FILE" 2>/dev/null || true
  }

  if [[ -z "${MCP_FS_SANDBOX:-}" ]]; then
    echo ""
    info "Filesystem Sandbox — restricts MCP file server access to a single directory"
    info "Recommendation: use the most restrictive path that fits your workflow"
    read -rp "  Sandbox path [default: $HOME/projects]: " sandbox_input
    sandbox_input="${sandbox_input:-$HOME/projects}"
  else
    sandbox_input="$MCP_FS_SANDBOX"
    info "Using MCP_FS_SANDBOX from .env: $sandbox_input"
  fi

  local validated_path; validated_path="$(validate_sandbox "$sandbox_input")"
  export MCP_FS_SANDBOX="$validated_path"
  mkdir -p "$validated_path"

  if grep -q "^MCP_FS_SANDBOX=" "$ENV_FILE" 2>/dev/null; then
    python3 -c "
import re
from pathlib import Path
p = Path('$ENV_FILE')
content = re.sub(r'^MCP_FS_SANDBOX=.*\$', 'MCP_FS_SANDBOX=$validated_path', p.read_text(), flags=re.MULTILINE)
p.write_text(content)
"
  else
    printf 'MCP_FS_SANDBOX=%s\n' "$validated_path" >> "$ENV_FILE"
  fi
  success "Filesystem sandbox: $validated_path"
}

# ── Install to Claude Code ─────────────────────────────────────────────────────

install_claude() {
  info "Installing to Claude Code..."
  local claude_dir="$HOME/.claude"
  local mcp_src="$OUT_DIR/claude-code/mcp-config.json"
  local mcp_dst="$HOME/.claude.json"

  mkdir -p "$claude_dir/skills"
  for skill_dir in "$OUT_DIR/claude-code/skills"/*/; do
    local skill_name; skill_name="$(basename "$skill_dir")"
    mkdir -p "$claude_dir/skills/$skill_name"
    cp "$skill_dir/skill.md" "$claude_dir/skills/$skill_name/skill.md"
  done
  success "Skills → $claude_dir/skills/"

  mkdir -p "$claude_dir/agents"
  find "$AGENTS_DIR" -name "*.md" \
    ! -path "*/integrations/*" ! -path "*README*" \
    ! -path "*CONTRIBUTING*" ! -path "*SECURITY*" \
    ! -path "*/strategy/*" ! -path "*/examples/*" \
    ! -path "*/scripts/*" | while IFS= read -r f; do
    local fname; fname="$(basename "$f")"
    # Guard: skip filenames with path separators (traversal attempt)
    [[ "$fname" == *"/"* || "$fname" == ".."* ]] && { warn "Skipping suspicious filename: $fname"; continue; }
    cp "$f" "$claude_dir/agents/$fname"
  done
  local agent_count; agent_count="$(find "$claude_dir/agents/" -name "*.md" | wc -l | tr -d ' ')"
  success "Agents ($agent_count personas) → $claude_dir/agents/"

  if [[ -f "$mcp_dst" ]]; then
    python3 - <<PYEOF
import json
from pathlib import Path

src  = json.loads(Path("$mcp_src").read_text())
dst_path = Path("$mcp_dst")
dst  = json.loads(dst_path.read_text())
dst.setdefault("mcpServers", {})
added = [k for k in src["mcpServers"] if k not in dst["mcpServers"]]
dst["mcpServers"].update(src["mcpServers"])
dst_path.write_text(json.dumps(dst, indent=2))
print(f"  Added: {', '.join(added) if added else 'none (already present)'}")
PYEOF
    success "MCP config merged → $mcp_dst"
  else
    warn "$mcp_dst not found — run Claude Code once, then re-run install.sh"
  fi

  warn "Restart Claude Code to activate MCP servers"
}

# ── Install to Codex ───────────────────────────────────────────────────────────

install_codex() {
  info "Installing to Codex..."
  local codex_dir="$HOME/.codex"
  local config_dst="$codex_dir/config.toml"
  local mcp_src="$OUT_DIR/codex/mcp-config.toml"

  [[ -d "$codex_dir" ]] || { warn "~/.codex not found — skipping Codex install"; return; }

  mkdir -p "$codex_dir/skills"
  for skill_dir in "$OUT_DIR/codex/skills"/*/; do
    local skill_name; skill_name="$(basename "$skill_dir")"
    mkdir -p "$codex_dir/skills/$skill_name"
    cp "$skill_dir/skill.md" "$codex_dir/skills/$skill_name/skill.md"
  done
  success "Skills → $codex_dir/skills/"

  mkdir -p "$codex_dir/rules"
  find "$AGENTS_DIR" -name "*.md" \
    ! -path "*/integrations/*" ! -path "*README*" \
    ! -path "*CONTRIBUTING*" ! -path "*SECURITY*" \
    ! -path "*/strategy/*" ! -path "*/examples/*" \
    ! -path "*/scripts/*" | while IFS= read -r f; do
    local fname; fname="agency-$(basename "$f")"
    [[ "$fname" == *"/"* || "$fname" == ".."* ]] && { warn "Skipping suspicious filename: $fname"; continue; }
    cp "$f" "$codex_dir/rules/$fname"
  done
  success "Agents → $codex_dir/rules/"

  if [[ -f "$config_dst" ]]; then
    python3 - <<PYEOF
import re
from pathlib import Path

new_blocks = Path("$mcp_src").read_text()
dst_path   = Path("$config_dst")
existing   = dst_path.read_text()

new_servers = re.findall(r'^\[mcp_servers\.([^\]\.]+)\]', new_blocks, re.MULTILINE)
added = []
for server in new_servers:
    if f"[mcp_servers.{server}]" not in existing:
        pattern = rf'(\[mcp_servers\.{re.escape(server)}\][^\[]*(?:\[mcp_servers\.{re.escape(server)}\.env\][^\[]*)?)'
        m = re.search(pattern, new_blocks, re.DOTALL)
        if m:
            block = m.group(1).strip()
            marker = "# END OMC MANAGED MCP REGISTRY"
            if marker in existing:
                existing = existing.replace(marker, block + "\n\n" + marker)
            else:
                existing += "\n" + block + "\n"
            added.append(server)

dst_path.write_text(existing)
print(f"  Added: {', '.join(added) if added else 'none (already present)'}")
PYEOF
    success "MCP config merged → $config_dst"
  else
    cp "$mcp_src" "$config_dst"
    success "MCP config written → $config_dst"
  fi

  warn "Restart Codex to activate MCP servers"
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
  echo "  MCP-Toolkit Installer  (security-hardened)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  check_deps
  detect_agents

  if (( ${#DETECTED_AGENTS[@]} == 0 )); then
    warn "No AI agents detected."
    info "Supported: Claude Code, Codex, Hermes, OpenClaw"
    read -rp "Continue anyway? [y/N]: " cont
    [[ "${cont:-n}" =~ ^[yY] ]] || exit 0
    DETECTED_AGENTS=("claude-code")
  else
    info "Detected: ${DETECTED_AGENTS[*]}"
  fi

  choose_preset
  collect_keys
  configure_sandbox

  info "Generating integration files..."
  bash "$SCRIPTS_DIR/convert.sh" "$PRESET"

  echo ""; info "Installing..."
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
  info "Installed to:  ${DETECTED_AGENTS[*]}"
  info "Sandbox:       $MCP_FS_SANDBOX"
  local server_count; server_count="$(grep -c '  - ' "$MCP_DIR/presets/${PRESET}.yaml" 2>/dev/null || echo '?')"
  info "Servers:       $server_count  ·  Skills: 11  ·  Agents: 205"
  echo ""
}

main "$@"
