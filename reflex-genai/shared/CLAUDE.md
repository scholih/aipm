# Reflex BV — Shared Claude Code Configuration

All persona CLAUDE.md files should inherit from this shared config by referencing it.

---

## Company Context

- **Company:** Reflex BV
- **Domain:** Workplace management solutions (access control, visitor management, workspace booking)
- **Location:** Netherlands
- **Language:** Dutch company, English documentation and code
- **Tone:** Professional, clear, concise

---

## Task Tracking

All task tracking via Beads. No exceptions.

```bash
bd ready                          # find available work
bd update <id> --status=in_progress  # claim a task
bd close <id> --reason="..."      # close when done
bd remember "insight"             # persist key findings
```

---

## Python Execution

Always use `uv run`. Never activate venvs manually.

```bash
uv run python script.py
uv run python -m module_name
uv run pytest tests/ -v
uv add <package>
```

---

## Local AI (Ollama)

Ollama is available at `http://localhost:11434`.

Use for all tasks involving sensitive or confidential content. Available models:

| Alias | Model | Use case |
|-------|-------|----------|
| fast | llama3.2:3b | Classification, tagging, yes/no |
| default | llama3.1:8b | Summarize, explain, draft |
| deep | llama3.1:70b | Deep analysis, reasoning |
| code | deepseek-coder-v2:16b | Code review |
| extract | mistral:7b | Structured JSON extraction |
| embed | nomic-embed-text | Embeddings |

---

## Knowledge Base

- **Obsidian vault:** `~/reflex-kb/`
- **Architecture:** See `reflex-genai/knowledge-base/ARCHITECTURE.md`
- Link to KB notes from Beads issues using `[[note]]` syntax
- Each persona has a home dashboard in the vault

---

## Sidecar Tools

```bash
# Global sidecar
uv run --directory ~/.claude/sidecar python fetch.py <url>
uv run --directory ~/.claude/sidecar python llm.py summarize <file>
uv run --directory ~/.claude/sidecar python data.py inspect <file>
uv run --directory ~/.claude/sidecar python diagram.py mermaid <spec>

# Per-repo sidecar (check _sidecar/ first)
uv run --directory _sidecar python <script>.py
```

---

## Data Privacy (MANDATORY)

- **Never send confidential client data to external APIs.** Use Ollama for any task involving sensitive content (client names, contracts, access control configurations, visitor logs).
- SharePoint and internal documents stay local. Use local embeddings (Smart Connections + Ollama) for search.
- When in doubt about data sensitivity: treat it as confidential and use Ollama.

---

## Git and Branching

- Feature work in worktrees (`.worktrees/` directory)
- No merge to main without testing and explicit confirmation
- Semantic versioning: MAJOR.MINOR.PATCH
