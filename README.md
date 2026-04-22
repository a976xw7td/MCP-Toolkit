# MCP-Toolkit

**一键部署 AI 工具包 — 11 个 MCP 服务器 + 11 个技能 + 205 个专家智能体**

**One-click AI toolkit — 11 MCP servers + 11 skills + 205 expert agents**

支持 Claude Code、Codex、Hermes、OpenClaw | Works with Claude Code, Codex, Hermes, OpenClaw

---

## 快速开始 / Quick Start

```bash
git clone --recurse-submodules https://github.com/a976xw7td/MCP-Toolkit.git
cd MCP-Toolkit
bash scripts/install.sh   # macOS / Linux / Windows Git Bash 或 WSL2
```

按照提示选择预设方案并输入 API 密钥即可（约 2 分钟）。  
Follow the prompts to choose a preset and enter API keys (~2 minutes).

---

## 平台兼容性 / Platform Compatibility

### 安装脚本 / install.sh

| 系统 | 运行方式 | 说明 |
|------|---------|------|
| macOS | 直接运行 | 完全支持 |
| Linux | 直接运行 | 完全支持 |
| Windows | Git Bash 或 WSL2 | 原生 CMD / PowerShell 不支持 bash |

> **Windows 用户**：安装 [Git for Windows](https://git-scm.com/download/win) 即可获得 Git Bash，右键文件夹选"Git Bash Here"运行脚本。

### Agent 支持情况 / Agent Support

| Agent | macOS | Linux | Windows | 备注 |
|-------|-------|-------|---------|------|
| **Claude Code** | ✅ | ✅ | ✅ | Windows 安装脚本需 Git Bash/WSL2 |
| **Codex** | ✅ | ✅ | ✅ | Windows 安装脚本需 Git Bash/WSL2 |
| **Hermes** | ✅ | ✅ | ❌ | Hermes 本身不支持 Windows |
| **OpenClaw** | ✅ | ✅ | ✅ | 仅安装技能；角色系统架构不同，205 个角色不适用 |

### 安装内容对照 / What Gets Installed

| 内容 | Claude Code | Codex | Hermes | OpenClaw |
|------|-------------|-------|--------|----------|
| 11 个技能 | ✅ | ✅ | ✅ | ✅ |
| MCP 服务器配置 | ✅ | ✅ | ✅ | ⚠️ 插件系统不同，需手动配置 |
| 205 个专家角色 | ✅ | ✅ | ✅ | ❌ OpenClaw 为单 workspace 架构，不支持多角色 |

---

## 包含内容 / What's Included

### MCP 服务器 / MCP Servers (11 个)

| 服务器 | 功能 | 运行时 | API 密钥 |
|--------|------|--------|---------|
| filesystem | 读写本地文件 | npx | 无需 |
| git | Git 操作 | uvx | 无需 |
| memory | 跨会话记忆 | npx | 无需 |
| sequential-thinking | 结构化推理 | npx | 无需 |
| fetch | 网页内容抓取 | uvx | 无需 |
| time | 时区/时间 | uvx | 无需 |
| desktop-commander | 终端命令执行 | npx | 无需 |
| context7 | 实时库文档注入 | npx | 无需 |
| github | GitHub 仓库操作 | npx | GitHub PAT (免费) |
| brave-search | 网络搜索 | npx | Brave API (免费层) |
| firecrawl | 深度网页爬取 | npx | Firecrawl API (免费层) |

### 技能 / Skills (11 个)

| 技能 | 描述 |
|------|------|
| autopilot | 自动驾驶 — 给目标，自动规划并执行 |
| ralph | 持久重试 — 循环直到任务完成且验证通过 |
| ultrawork | 超深工作模式 — 最高质量输出 |
| team | 多智能体协作 — N 个工作者并行执行 |
| ultraqa | 全面质量审查 — 功能、回归、安全、可访问性 |
| deep-dive | 深度代码分析 — 从源码理解系统架构 |
| trace | 根因分析 — 追踪 bug 到具体源头 |
| wiki | 文档生成 — README、API 文档、架构文档 |
| scientific-writing | 学术写作助手 — 论文、报告、文献综述 |
| review | 代码审查 — 正确性、性能、安全、可维护性 |
| security-review | 安全审计 — OWASP Top 10 全覆盖 |

### 专家智能体 / Expert Agents (205 个)

来自 [agency-agents](https://github.com/msitarzewski/agency-agents) 的 205 个专业智能体，涵盖：

工程 · 设计 · 营销 · 销售 · 金融 · 产品 · 测试 · 游戏开发 · 安全 · 学术 · 更多

> 安装后位于 `~/.claude/agents/`（Claude Code）和 `~/.codex/rules/`（Codex）。

---

## 预设方案 / Presets

### minimal（推荐新手）
- 无需任何 API 密钥
- 8 个 MCP 服务器
- 首次运行下载约 80–120 MB

### developer（推荐开发者）
- 需要免费 GitHub Personal Access Token
- 10 个 MCP 服务器（新增 GitHub + 搜索）
- 获取地址：https://github.com/settings/tokens（权限：repo, read:user）

### full（全功能）
- 需要 GitHub PAT
- 可选 Brave Search API + Firecrawl API（均有免费层）
- 11 个 MCP 服务器，全功能开启

---

## 前置依赖 / Requirements

| 依赖 | 用途 | 安装 |
|------|------|------|
| Node.js 18+ | 运行 npx 类 MCP 服务器 | https://nodejs.org |
| uv | 运行 uvx 类 MCP 服务器（git/fetch/time）| `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| Python 3.8+ | 安装脚本内部使用 | 通常已预装 |
| git | 克隆本仓库 | https://git-scm.com |

**Windows 额外要求**：Git Bash（随 Git for Windows 附带）或 WSL2，用于运行 bash 安装脚本。MCP 服务器本身原生支持 Windows。

---

## 安装后能做什么 / What You Can Do After Install

### 用 autopilot 自动完成任务
```
autopilot: 帮我建一个有登录功能的 React 项目
```

### 用 team 模式并行开发
```
/team 4:executor "实现用户管理 CRUD API 和测试"
```

### 用 review 做代码审查
```
review the authentication module
```

### 用 security-review 做安全审计
```
security-review src/api/
```

### 用 deep-dive 理解陌生代码
```
deep-dive 支付处理模块是怎么工作的
```

### 激活专家角色（Claude Code / Codex）
```
用 Backend Architect 帮我设计这个项目的数据库结构
用 UI Designer 帮我生成一个漂亮的 HTML 报告模板
```

---

## 手动安装 / Manual Install

如果自动安装脚本遇到问题：

**Claude Code:**
```bash
bash scripts/convert.sh minimal
# 技能
cp -r integrations/claude-code/skills/* ~/.claude/skills/
# 角色
mkdir -p ~/.claude/agents
find agents -name "*.md" ! -path "*/integrations/*" ! -path "*README*" \
  ! -path "*/strategy/*" ! -path "*/scripts/*" \
  -exec cp {} ~/.claude/agents/ \;
# MCP 配置：将 integrations/claude-code/mcp-config.json 内容合并到 ~/.claude.json
```

**Codex:**
```bash
bash scripts/convert.sh minimal
cp -r integrations/codex/skills/* ~/.codex/skills/
# MCP 配置：将 integrations/codex/mcp-config.toml 内容追加到 ~/.codex/config.toml
```

**Hermes:**
```bash
bash scripts/convert.sh minimal
cp -r integrations/hermes/skills/* ~/.hermes/skills/
cp integrations/hermes/mcp-config.yaml ~/.hermes/mcp-config.yaml
hermes reload
```

---

## 贡献 / Contributing

欢迎提交 PR！新增 MCP 服务器请在 `mcp/servers/` 下添加 YAML 配置文件。

PRs welcome! To add a new MCP server, add a YAML config in `mcp/servers/`.

---

## 许可证 / License

MIT

---

*agency-agents submodule © [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents)*
