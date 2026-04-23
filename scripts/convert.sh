#!/usr/bin/env bash
# convert.sh — Generate agent-specific configs from universal skill/MCP definitions
# Cross-platform: uses pathlib.Path throughout; validates TOML/JSON before write
set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$TOOLKIT_DIR/skills"
MCP_DIR="$TOOLKIT_DIR/mcp"
OUT_DIR="$TOOLKIT_DIR/integrations"

PRESET="${1:-minimal}"

log() { echo "[convert] $*"; }

# ── Load .env ─────────────────────────────────────────────────────────────────

if [[ -f "$TOOLKIT_DIR/.env" ]]; then
  set -o allexport
  # shellcheck disable=SC1090
  source "$TOOLKIT_DIR/.env" 2>/dev/null || true
  set +o allexport
fi

# ── Helpers ────────────────────────────────────────────────────────────────────

yaml_list() {
  local file="$1" key="$2" in_block=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^${key}: ]]; then in_block=1; continue; fi
    if (( in_block == 1 )); then
      if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
        echo "${BASH_REMATCH[1]}"
      else
        in_block=0
      fi
    fi
  done < "$file"
}

# Shared Python helper included verbatim into all inline Python blocks below.
# Uses pathlib.Path for cross-platform path handling (no hardcoded separators).
parse_server_py() {
  cat <<'PYEOF'
import os, re
from pathlib import Path

def _toml_escape(s: str) -> str:
    """Escape a string for safe embedding in a TOML basic string."""
    return s.replace('\\', '\\\\').replace('"', '\\"')

def _expand_env(s: str) -> str:
    """Replace ${VAR} / $VAR with environment values; preserve literal if unset."""
    return re.sub(r'\$\{(\w+)\}', lambda m: os.environ.get(m.group(1), m.group(0)), s)

def parse_server(yaml_path: str) -> tuple:
    content = Path(yaml_path).read_text(encoding='utf-8')

    def scalar(key):
        m = re.search(rf'^{key}:\s*(.+)$', content, re.MULTILINE)
        return m.group(1).strip().strip('"') if m else ""

    def get_list(key):
        # Inline: args: ["-y", "pkg", "${HOME}"]
        m = re.search(rf'^{key}:\s*\[(.+)\]', content, re.MULTILINE)
        if m:
            items = []
            for part in re.split(r',\s*', m.group(1)):
                part = part.strip().strip('"').strip("'")
                if part:
                    items.append(_expand_env(part))
            return items
        # Block list
        items, in_block = [], False
        for line in content.splitlines():
            if re.match(rf'^{key}:', line):
                in_block = True; continue
            if in_block:
                m2 = re.match(r'^\s+-\s+"?([^"]+)"?', line)
                if m2:
                    items.append(_expand_env(m2.group(1)))
                elif line.strip() and not line.startswith(' '):
                    in_block = False
        return items

    env = {}
    in_env = False
    for line in content.splitlines():
        if re.match(r'^env:', line):
            in_env = True; continue
        if in_env:
            m = re.match(r'^\s+(\w+):\s*"?\$\{(\w+)\}"?', line)
            if m:
                k, env_key = m.group(1), m.group(2)
                env[k] = os.environ.get(env_key, f"${{{env_key}}}")
            elif line.strip() and not line.startswith(' '):
                in_env = False

    return scalar("command"), get_list("args"), env
PYEOF
}

# ── Validate preset ────────────────────────────────────────────────────────────

PRESET_FILE="$MCP_DIR/presets/${PRESET}.yaml"
if [[ ! -f "$PRESET_FILE" ]]; then
  echo "Error: preset '$PRESET' not found at $PRESET_FILE" >&2
  echo "Available: $(ls "$MCP_DIR/presets/" | sed 's/\.yaml//' | tr '\n' ' ')" >&2
  exit 1
fi

log "Using preset: $PRESET"
SERVERS=()
while IFS= read -r line; do SERVERS+=("$line"); done < <(yaml_list "$PRESET_FILE" servers)
log "Servers: ${SERVERS[*]}"

# ── Output directories ─────────────────────────────────────────────────────────

mkdir -p \
  "$OUT_DIR/claude-code/skills" \
  "$OUT_DIR/codex/skills" \
  "$OUT_DIR/hermes/skills" \
  "$OUT_DIR/openclaw/skills"

# ── Claude Code MCP config (JSON) ─────────────────────────────────────────────

log "Generating Claude Code MCP config..."
CLAUDE_MCP="$OUT_DIR/claude-code/mcp-config.json"
SERVERS_CSV="$( IFS=','; echo "${SERVERS[*]}" )"

python3 - <<PYEOF
import json, sys
from pathlib import Path
$(parse_server_py)

servers_dir = Path("$MCP_DIR") / "servers"
servers = [s.strip() for s in "$SERVERS_CSV".split(",")]

mcp_servers = {}
for name in servers:
    yaml_path = servers_dir / f"{name}.yaml"
    if not yaml_path.exists():
        print(f"  [warn] not found: {yaml_path}", file=sys.stderr); continue
    command, args, env = parse_server(str(yaml_path))
    entry = {"command": command, "args": args}
    if env:
        entry["env"] = env
    mcp_servers[name] = entry

out = Path("$CLAUDE_MCP")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({"mcpServers": mcp_servers}, indent=2))
print(f"  Written: $CLAUDE_MCP ({len(mcp_servers)} servers)")
PYEOF

# ── Codex MCP config (TOML) ───────────────────────────────────────────────────

log "Generating Codex MCP config..."
CODEX_MCP="$OUT_DIR/codex/mcp-config.toml"

python3 - <<PYEOF
import sys
from pathlib import Path
$(parse_server_py)

servers_dir = Path("$MCP_DIR") / "servers"
servers = [s.strip() for s in "$SERVERS_CSV".split(",")]

lines = [
    "# MCP-Toolkit — generated config",
    "# Merge this into ~/.codex/config.toml",
    "",
]

for name in servers:
    yaml_path = servers_dir / f"{name}.yaml"
    if not yaml_path.exists():
        print(f"  [warn] not found: {yaml_path}", file=sys.stderr); continue
    command, args, env = parse_server(str(yaml_path))

    # Always emit a non-empty args array (bare 'args =' is invalid TOML)
    toml_args = "[" + ", ".join(f'"{_toml_escape(a)}"' for a in args) + "]"
    lines.append(f"[mcp_servers.{name}]")
    lines.append(f'command = "{_toml_escape(command)}"')
    lines.append(f"args = {toml_args}")
    if env:
        lines.append(f"[mcp_servers.{name}.env]")
        for k, v in env.items():
            lines.append(f'{k} = "{_toml_escape(v)}"')
    lines.append("")

out = Path("$CODEX_MCP")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(lines))
print(f"  Written: $CODEX_MCP ({len([l for l in lines if l.startswith('[mcp_servers.') and '.env]' not in l])} servers)")
PYEOF

# ── Hermes MCP config (YAML) ──────────────────────────────────────────────────

log "Generating Hermes MCP config..."
HERMES_MCP="$OUT_DIR/hermes/mcp-config.yaml"

python3 - <<PYEOF
import sys
from pathlib import Path
$(parse_server_py)

servers_dir = Path("$MCP_DIR") / "servers"
servers = [s.strip() for s in "$SERVERS_CSV".split(",")]

lines = ["mcpServers:"]
for name in servers:
    yaml_path = servers_dir / f"{name}.yaml"
    if not yaml_path.exists():
        continue
    command, args, env = parse_server(str(yaml_path))
    lines.append(f"  {name}:")
    lines.append(f"    command: {command}")
    if args:
        lines.append("    args: [" + ", ".join(repr(a) for a in args) + "]")
    if env:
        lines.append("    env:")
        for k, v in env.items():
            lines.append(f'      {k}: "{v}"')

out = Path("$HERMES_MCP")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(lines) + "\n")
print(f"  Written: $HERMES_MCP")
PYEOF

# ── Skills: Claude Code ────────────────────────────────────────────────────────

log "Copying skills for Claude Code..."
for skill_file in "$SKILLS_DIR"/*.md; do
  skill_name="$(basename "$skill_file" .md)"
  mkdir -p "$OUT_DIR/claude-code/skills/$skill_name"
  cp "$skill_file" "$OUT_DIR/claude-code/skills/$skill_name/skill.md"
done
log "  $(ls "$OUT_DIR/claude-code/skills" | wc -l | tr -d ' ') skills written"

# ── Skills: Codex ─────────────────────────────────────────────────────────────

log "Copying skills for Codex..."
for skill_file in "$SKILLS_DIR"/*.md; do
  skill_name="$(basename "$skill_file" .md)"
  mkdir -p "$OUT_DIR/codex/skills/$skill_name"
  cp "$skill_file" "$OUT_DIR/codex/skills/$skill_name/skill.md"
done
log "  $(ls "$OUT_DIR/codex/skills" | wc -l | tr -d ' ') skills written"

# ── Skills: Hermes ────────────────────────────────────────────────────────────

log "Converting skills for Hermes..."
for skill_file in "$SKILLS_DIR"/*.md; do
  skill_name="$(basename "$skill_file" .md)"
  category="$(python3 -c "
import re
content = open('$skill_file').read() if '$skill_file'.endswith('.md') else ''
m = re.search(r'^category:\s*(.+)$', content, re.MULTILINE)
print(m.group(1).strip() if m else 'general')
" 2>/dev/null || echo "general")"
  tags="$(python3 -c "
import re
content = open('$skill_file').read()
m = re.search(r'^tags:\s*\[([^\]]+)\]', content, re.MULTILINE)
print(', '.join(t.strip() for t in m.group(1).split(',')) if m else 'general')
" 2>/dev/null || echo "general")"

  hermes_dir="$OUT_DIR/hermes/skills/$category/$skill_name"
  mkdir -p "$hermes_dir"
  python3 -c "
import re
from pathlib import Path
content = Path('$skill_file').read_text(encoding='utf-8')
block = 'metadata:\n  hermes:\n    tags: [$tags]\n    category: $category\n'
content = re.sub(r'^(---\n)', r'\1' + block, content, count=1)
Path('$hermes_dir/skill.md').write_text(content)
"
done
log "  Skills written to $OUT_DIR/hermes/skills/"

# ── Skills: OpenClaw ──────────────────────────────────────────────────────────

log "Copying skills for OpenClaw..."
for skill_file in "$SKILLS_DIR"/*.md; do
  skill_name="$(basename "$skill_file" .md)"
  mkdir -p "$OUT_DIR/openclaw/skills/$skill_name"
  cp "$skill_file" "$OUT_DIR/openclaw/skills/$skill_name/SKILL.md"
done
log "  $(ls "$OUT_DIR/openclaw/skills" | wc -l | tr -d ' ') skills written"

# ── Summary ────────────────────────────────────────────────────────────────────

log ""
log "Done. Generated integrations:"
log "  Claude Code: $OUT_DIR/claude-code/"
log "  Codex:       $OUT_DIR/codex/"
log "  Hermes:      $OUT_DIR/hermes/"
log "  OpenClaw:    $OUT_DIR/openclaw/"
log ""
log "Next: run install.sh to deploy to your agents."
