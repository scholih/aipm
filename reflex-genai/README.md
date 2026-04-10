# Reflex BV GenAI Environment

Structured GenAI environment for Reflex BV workplace management. 8 persona-based configurations running on Windows laptops with Microsoft Copilot + Claude integration, local Ollama inference, and shared knowledge bases.

> **DISCLAIMER:** This setup was designed and built on macOS by someone without a Windows machine. **Nothing has been tested on Windows.** The PowerShell scripts, path conventions, and Ollama/uv instructions are based on documentation and best practices, but must be validated on an actual Windows 11 laptop before rollout. PRs and issues welcome — especially from Windows users.

> **STATUS:** Draft / Proof of concept. Not production-ready.

## Architecture

```
+-------------------+     +-------------------------+     +-------------------+
|  Windows Laptop   |     |   AI Layer              |     |  Knowledge Base   |
|                   |     |                         |     |                   |
|  MS Copilot ------+---->|  Claude Code CLI        |     |  Obsidian Vault   |
|  (licensed)       |     |  + Persona CLAUDE.md    +---->|  (local brain)    |
|                   |     |                         |     |                   |
|  VS Code / Edge   |     |  Sidecar (uv run)      |     |  SharePoint       |
|                   |     |  + Ollama (local LLM)   +---->|  (collaboration)  |
+-------------------+     +-------------------------+     +-------------------+
                                     |
                          +----------+----------+
                          |  Tooling Layer       |
                          |                      |
                          |  Beads (tracking)    |
                          |  Serena (code nav)   |
                          |  Superpowers (skills)|
                          +---------------------+
```

## Persona Matrix

| Persona | Beads | Serena | Superpowers | Sidecar Tools | Ollama Models |
|---------|-------|--------|-------------|---------------|---------------|
| Tech Subject Expert | eval tracking | OSS code nav | brainstorm | fetch, llm, diagram | default, extract |
| Tech Solution Architect | decisions | full | full suite | fetch, llm, diagram, data | default, deep, code |
| Tech Developer | issues | full | full (TDD, debug) | full suite | all tiers |
| Tester | test cases | - | verification | llm | default, fast |
| Helpdesk | tickets | - | - | fetch, llm | fast, default |
| Marketing | campaigns | - | brainstorm | fetch, llm, diagram | default, extract |
| CEO | decisions | - | brainstorm | llm, data | fast, default |
| CTO | roadmap | full | full suite | llm, diagram, data | default, deep |

## Knowledge Base Architecture

| Layer | Tool | Purpose | Storage |
|-------|------|---------|---------|
| Personal brain | Obsidian | Notes, thinking, drafts | Local vault |
| Team collaboration | SharePoint | Shared docs, approvals | Microsoft 365 |
| Cheap AI inference | Ollama | Summarize, classify, extract | Local GPU/CPU |
| Complex reasoning | Claude API | Architecture, code gen, analysis | API calls |

Obsidian vaults sync via OneDrive or network share. Each persona gets a vault template with relevant folders and templates pre-configured.

## Cost Model

| Component | Cost | Notes |
|-----------|------|-------|
| Ollama | Free | Local inference, no data leaves laptop |
| Microsoft Copilot | Already licensed | Bundled with M365 |
| Claude API | Per-use | Only for complex tasks beyond Ollama |
| Obsidian | Free | Community edition, no license needed |
| Beads / Serena | Free | Open source tooling |

Route simple tasks (classification, summarization, extraction) to Ollama. Reserve Claude for multi-step reasoning, code generation, and architectural decisions.

## Quick Start

1. Run `setup/install.ps1` on the Windows laptop
2. Copy your persona's `CLAUDE.md` to `~/.claude/CLAUDE.md`
3. Open Obsidian and select the shared vault
4. Run `claude` in your terminal to verify the setup

See [setup/INSTALL.md](setup/INSTALL.md) for detailed installation steps.
