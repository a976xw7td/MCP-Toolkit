#!/usr/bin/env bash
# convert.sh — Generate agent-specific configs from universal skill/MCP definitions
set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$TOOLKIT_DIR/skills"
MCP_DIR="$TOOLKIT_DIR/mcp"
OUT_DIR="$TOOLKIT_DIR/integrations"

PRESET="${1:-minimal}"

log() { echo "[convert] $*"; }

# ── Helpers ────────────────────────────────────────────────────────────────────

yaml_list() {
  local file="$1" key="$2" in_block=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^${key}: ]]; then in_block=1; continue; fi
    if [[ $in_block -eq 1 ]]; then
      if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
        echo "${BASH_REMATCH[1]}"
      else
        in_block=0
      fi
    fi
  done < "$file"
}

# Shared Python helper: parse a single server yaml into a dict
# Usage: parse_server_yaml <yaml_path>
parse_server_py() {
  cat <<'PYEOF'
import os, re

def parse_server(yaml_path):
    with open(yaml_path) as f:
        content = f.read()

    def get_scalar(key):
        m = re.search(rf'^{key}:\s*(.+)$', content, re.MULTILINE)
        return m.group(1).strip().strip('"') if m else ""

    def get_list(key):
        # Handle inline list: args: ["-y", "pkg", "${HOME}"]
        m = re.search(rf'^{key}:\s*\[(.+)\]', content, re.MULTILINE)
        if m:
            raw = m.group(1)
            # Split on commas not inside quotes
            items = []
            for part in re.split(r',\s*', raw):
                part = part.strip().strip('"').strip("'")
                if part:
                    # Expand ${HOME} style vars
                    part = re.sub(r'\$\{(\w+)\}', lambda x: os.environ.get(x.group(1), x.group(0)), part)
                    items.append(part)
            return items
        # Handle block list:
        #   - "item"
        items, in_block = [], False
        for line in content.splitlines():
            if re.match(rf'^{key}:', line):
                in_block = True; continue
            if in_block:
                m2 = re.match(r'^\s+-\s+"?([^"]+)"?', line)
                if m2: items.append(m2.group(1))
                else: in_block = False
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
            elif not line.startswith(" ") and line.strip():
                in_env = False

    return get_scalar("command"), get_list("args"), env
PYEOF
}

# ── Load preset ────────────────────────────────────────────────────────────────

PRESET_FILE="$MCP_DIR/presets/${PRESET}.yaml"
if [[ ! -f "$PRESET_FILE" ]]; then
  echo "Error: preset '$PRESET' not found at $PRESET_FILE" >&2
  echo "Available presets: $(ls "$MCP_DIR/presets/" | sed 's/\.yaml//' | tr '\n' ' ')" >&2
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

python3 - <<PYEOF
import json, os, re, sys
$(parse_server_py)

servers_dir = os.path.join("$MCP_DIR", "servers")
servers = [s.strip() for s in "$( IFS=','; echo "${SERVERS[*]}" )".split(",")]

mcp_servers = {}
for name in servers:
    yaml_path = os.path.join(servers_dir, f"{name}.yaml")
    if not os.path.exists(yaml_path):
        print(f"  [warn] not found: {yaml_path}", file=sys.stderr); continue
    command, args, env = parse_server(yaml_path)
    entry = {"command": command, "args": args}
    if env: entry["env"] = env
    mcp_servers[name] = entry

with open("$CLAUDE_MCP", "w") as f:
    json.dump({"mcpServers": mcp_servers}, f, indent=2)
print(f"  Written: $CLAUDE_MCP")
PYEOF

# ── Codex MCP config (TOML) ───────────────────────────────────────────────────

log "Generating Codex MCP config..."
CODEX_MCP="$OUT_DIR/codex/mcp-config.toml"

python3 - <<PYEOF
import os, re
$(parse_server_py)

servers_dir = os.path.join("$MCP_DIR", "servers")
servers = [s.strip() for s in "$( IFS=','; echo "${SERVERS[*]}" )".split(",")]

lines = ["# MCP-Toolkit — generated config", "# Merge this into ~/.codex/config.toml", ""]

for name in servers:
    yaml_path = os.path.join(servers_dir, f"{name}.yaml")
    if not os.path.exists(yaml_path):
        continue
    command, args, env = parse_server(yaml_path)

    # TOML array: ["a", "b"]
    toml_args = "[" + ", ".join(f'"{a}"' for a in args) + "]"
    lines.append(f"[mcp_servers.{name}]")
    lines.append(f'command = "{command}"')
    lines.append(f"args = {toml_args}")
    if env:
        lines.append(f"[mcp_servers.{name}.env]")
        for k, v in env.items():
            lines.append(f'{k} = "{v}"')
    lines.append("")

with open("$CODEX_MCP", "w") as f:
    f.write("\n".join(lines))
print(f"  Written: $CODEX_MCP")
PYEOF

# ── Hermes MCP config (YAML) ──────────────────────────────────────────────────

log "Generating Hermes MCP config..."
HERMES_MCP="$OUT_DIR/hermes/mcp-config.yaml"

python3 - <<PYEOF
import os, re
$(parse_server_py)

servers_dir = os.path.join("$MCP_DIR", "servers")
servers = [s.strip() for s in "$( IFS=','; echo "${SERVERS[*]}" )".split(",")]

lines = ["mcpServers:"]
for name in servers:
    yaml_path = os.path.join(servers_dir, f"{name}.yaml")
    if not os.path.exists(yaml_path):
        continue
    command, args, env = parse_server(yaml_path)
    lines.append(f"  {name}:")
    lines.append(f"    command: {command}")
    if args:
        lines.append(f"    args: [{', '.join(repr(a) for a in args)}]")
    if env:
        lines.append("    env:")
        for k, v in env.items():
            lines.append(f'      {k}: "{v}"')

with open("$HERMES_MCP", "w") as f:
    f.write("\n".join(lines) + "\n")
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
  category=$(python3 -c "
import re
content = open('$skill_file').read()
m = re.search(r'^category:\s*(.+)$', content, re.MULTILINE)
print(m.group(1).strip() if m else 'general')
" 2>/dev/null || echo "general")
  tags=$(python3 -c "
import re
content = open('$skill_file').read()
m = re.search(r'^tags:\s*\[([^\]]+)\]', content, re.MULTILINE)
print(', '.join(t.strip() for t in m.group(1).split(',')) if m else 'general')
" 2>/dev/null || echo "general")

  hermes_dir="$OUT_DIR/hermes/skills/$category/$skill_name"
  mkdir -p "$hermes_dir"
  python3 -c "
import re
content = open('$skill_file').read()
block = 'metadata:\n  hermes:\n    tags: [$tags]\n    category: $category\n'
content = re.sub(r'^(---\n)', r'\1' + block, content, count=1)
open('$hermes_dir/skill.md', 'w').write(content)
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
log "  Skills written to $OUT_DIR/openclaw/skills/"

# ── Summary ────────────────────────────────────────────────────────────────────

log ""
log "Done! Generated integrations:"
log "  Claude Code: $OUT_DIR/claude-code/"
log "  Codex:       $OUT_DIR/codex/"
log "  Hermes:      $OUT_DIR/hermes/"
log "  OpenClaw:    $OUT_DIR/openclaw/"
log ""
log "Next: run install.sh to deploy to your agents."
