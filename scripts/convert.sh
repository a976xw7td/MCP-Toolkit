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

yaml_get() {
  # Extract a scalar value from a simple YAML file
  local file="$1" key="$2"
  grep -E "^${key}:" "$file" | head -1 | sed "s/^${key}:[[:space:]]*//" | tr -d '"'
}

yaml_list() {
  # Extract a YAML list (items starting with "  - ")
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

# ── Load preset ────────────────────────────────────────────────────────────────

PRESET_FILE="$MCP_DIR/presets/${PRESET}.yaml"
if [[ ! -f "$PRESET_FILE" ]]; then
  echo "Error: preset '$PRESET' not found at $PRESET_FILE" >&2
  echo "Available presets: $(ls "$MCP_DIR/presets/" | sed 's/\.yaml//' | tr '\n' ' ')" >&2
  exit 1
fi

log "Using preset: $PRESET"
mapfile -t SERVERS < <(yaml_list "$PRESET_FILE" servers)
log "Servers: ${SERVERS[*]}"

# ── Output directories ─────────────────────────────────────────────────────────

mkdir -p \
  "$OUT_DIR/claude-code" \
  "$OUT_DIR/hermes/skills" \
  "$OUT_DIR/openclaw/skills"

# ── Build Claude Code MCP config (claude_desktop_config.json format) ───────────

log "Generating Claude Code MCP config..."
CLAUDE_MCP="$OUT_DIR/claude-code/mcp-config.json"

python3 - <<PYEOF
import json, os, re, sys

servers_dir = os.path.join("$MCP_DIR", "servers")
servers = "$( IFS=','; echo "${SERVERS[*]}" )".split(",")
env_vars = {k: v for k, v in os.environ.items()}

mcp_servers = {}
for name in servers:
    name = name.strip()
    yaml_path = os.path.join(servers_dir, f"{name}.yaml")
    if not os.path.exists(yaml_path):
        print(f"  [warn] server config not found: {yaml_path}", file=sys.stderr)
        continue

    cfg = {}
    with open(yaml_path) as f:
        content = f.read()

    def get_scalar(key):
        m = re.search(rf'^{key}:\s*(.+)$', content, re.MULTILINE)
        return m.group(1).strip().strip('"') if m else ""

    def get_list(key):
        items = []
        in_block = False
        for line in content.splitlines():
            if re.match(rf'^{key}:', line):
                in_block = True
                continue
            if in_block:
                m = re.match(r'^\s+-\s+"?([^"]+)"?', line)
                if m:
                    items.append(m.group(1))
                else:
                    in_block = False
        return items

    command = get_scalar("command")
    args = get_list("args")

    # Parse env block
    env = {}
    in_env = False
    for line in content.splitlines():
        if re.match(r'^env:', line):
            in_env = True
            continue
        if in_env:
            m = re.match(r'^\s+(\w+):\s*"?\$\{(\w+)\}"?', line)
            if m:
                key, env_key = m.group(1), m.group(2)
                if env_key in os.environ:
                    env[key] = os.environ[env_key]
                else:
                    env[key] = f"\${{{env_key}}}"
            elif not line.startswith(" ") and line.strip():
                in_env = False

    entry = {"command": command, "args": args}
    if env:
        entry["env"] = env

    mcp_servers[name] = entry

out = {"mcpServers": mcp_servers}
with open("$CLAUDE_MCP", "w") as f:
    json.dump(out, f, indent=2)
print(f"  Written: $CLAUDE_MCP")
PYEOF

# ── Copy skills for Claude Code ────────────────────────────────────────────────

log "Copying skills for Claude Code..."
CLAUDE_SKILLS="$OUT_DIR/claude-code/skills"
mkdir -p "$CLAUDE_SKILLS"
for skill_file in "$SKILLS_DIR"/*.md; do
  skill_name="$(basename "$skill_file" .md)"
  mkdir -p "$CLAUDE_SKILLS/$skill_name"
  cp "$skill_file" "$CLAUDE_SKILLS/$skill_name/skill.md"
done
log "  Skills: $(ls "$CLAUDE_SKILLS" | wc -l | tr -d ' ') skills written"

# ── Build Hermes MCP config ────────────────────────────────────────────────────

log "Generating Hermes MCP config..."
HERMES_MCP="$OUT_DIR/hermes/mcp-config.yaml"

python3 - <<PYEOF
import os, re, sys

servers_dir = os.path.join("$MCP_DIR", "servers")
servers = "$( IFS=','; echo "${SERVERS[*]}" )".split(",")

lines = ["mcpServers:"]
for name in servers:
    name = name.strip()
    yaml_path = os.path.join(servers_dir, f"{name}.yaml")
    if not os.path.exists(yaml_path):
        continue

    with open(yaml_path) as f:
        content = f.read()

    def get_scalar(key):
        m = re.search(rf'^{key}:\s*(.+)$', content, re.MULTILINE)
        return m.group(1).strip().strip('"') if m else ""

    def get_list(key):
        items = []
        in_block = False
        for line in content.splitlines():
            if re.match(rf'^{key}:', line):
                in_block = True; continue
            if in_block:
                m = re.match(r'^\s+-\s+"?([^"]+)"?', line)
                if m: items.append(m.group(1))
                else: in_block = False
        return items

    command = get_scalar("command")
    args = get_list("args")

    lines.append(f"  {name}:")
    lines.append(f"    command: {command}")
    if args:
        lines.append(f"    args: [{', '.join(repr(a) for a in args)}]")

    in_env = False
    env_lines = []
    for line in content.splitlines():
        if re.match(r'^env:', line):
            in_env = True; continue
        if in_env:
            m = re.match(r'^\s+(\w+):\s*"?\$\{(\w+)\}"?', line)
            if m:
                key, env_key = m.group(1), m.group(2)
                env_lines.append(f"      {key}: \"{os.environ.get(env_key, f'${{{env_key}}}')}\")
            elif not line.startswith(" ") and line.strip():
                in_env = False
    if env_lines:
        lines.append("    env:")
        lines.extend(env_lines)

with open("$HERMES_MCP", "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"  Written: $HERMES_MCP")
PYEOF

# ── Convert skills for Hermes ──────────────────────────────────────────────────

log "Converting skills for Hermes..."
for skill_file in "$SKILLS_DIR"/*.md; do
  skill_name="$(basename "$skill_file" .md)"
  # Read tags from frontmatter
  tags=$(python3 -c "
import re, sys
content = open('$skill_file').read()
m = re.search(r'^tags:\s*\[([^\]]+)\]', content, re.MULTILINE)
if m:
    tags = [t.strip() for t in m.group(1).split(',')]
    print(', '.join(tags))
" 2>/dev/null || echo "general")
  category=$(python3 -c "
import re
content = open('$skill_file').read()
m = re.search(r'^category:\s*(.+)$', content, re.MULTILINE)
print(m.group(1).strip() if m else 'general')
" 2>/dev/null || echo "general")

  hermes_skill_dir="$OUT_DIR/hermes/skills/$category/$skill_name"
  mkdir -p "$hermes_skill_dir"

  # Add hermes metadata block after frontmatter
  python3 - <<INNER
import re
content = open('$skill_file').read()
# Insert hermes tags into frontmatter
hermes_block = f"\nmetadata:\n  hermes:\n    tags: [{tags}]\n    category: $category"
content = re.sub(r'^(---\n)', r'\1' + hermes_block.lstrip('\n') + '\n', content, count=1)
open('$hermes_skill_dir/skill.md', 'w').write(content)
INNER
done
log "  Skills written to $OUT_DIR/hermes/skills/"

# ── Convert skills for OpenClaw ────────────────────────────────────────────────

log "Converting skills for OpenClaw..."
for skill_file in "$SKILLS_DIR"/*.md; do
  skill_name="$(basename "$skill_file" .md)"
  openclaw_skill_dir="$OUT_DIR/openclaw/skills/$skill_name"
  mkdir -p "$openclaw_skill_dir"
  # OpenClaw uses SKILL.md (uppercase)
  cp "$skill_file" "$openclaw_skill_dir/SKILL.md"
done
log "  Skills written to $OUT_DIR/openclaw/skills/"

# ── Summary ────────────────────────────────────────────────────────────────────

log ""
log "Done! Generated integrations:"
log "  Claude Code: $OUT_DIR/claude-code/"
log "  Hermes:      $OUT_DIR/hermes/"
log "  OpenClaw:    $OUT_DIR/openclaw/"
log ""
log "Next: run install.sh to deploy to your agents."
