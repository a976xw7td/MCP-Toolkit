# MCP-Toolkit — Production Docker Image
# Base: node:20-alpine (minimal footprint, ~180MB)
# Includes: Node.js 20, Python 3, uv, bash, git
FROM node:20-alpine AS base

RUN apk add --no-cache \
    python3 \
    py3-pip \
    bash \
    curl \
    git \
    ca-certificates

# Install uv (Python package runner for uvx-based MCP servers)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /toolkit

# Pre-install npm packages (warms the npx cache for offline/faster startup)
RUN npm install -g \
    @modelcontextprotocol/server-filesystem \
    @modelcontextprotocol/server-memory \
    @modelcontextprotocol/server-sequential-thinking \
    @upstash/context7-mcp \
    @wonderwhy-er/desktop-commander \
    supergateway

# Pre-install uvx packages
RUN uvx mcp-server-git --help &>/dev/null || true
RUN uvx mcp-server-fetch --help &>/dev/null || true
RUN uvx mcp-server-time --help &>/dev/null || true

# Copy toolkit source (agents submodule must be bind-mounted as a volume)
COPY scripts/ scripts/
COPY mcp/     mcp/
COPY skills/  skills/

# Default sandbox: /workspace (mount a host directory here)
ENV MCP_FS_SANDBOX=/workspace
ENV PRESET=minimal

VOLUME ["/workspace", "/root/.claude", "/root/.codex", "/root/.hermes"]

# Default: run the installer
ENTRYPOINT ["bash", "scripts/install.sh"]
