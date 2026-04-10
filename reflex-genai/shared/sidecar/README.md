# Sidecar Tools — Reflex BV

Offload heavy or repetitive tasks to sidecar scripts instead of processing inline. All invoked via `uv run`.

## Available Tools

| Script | Purpose | Examples |
|--------|---------|---------|
| `fetch.py` | Web fetching | Vendor docs, competitor sites, API docs |
| `llm.py` | Local LLM tasks | Summarize, extract, classify, review |
| `data.py` | Data analysis | DuckDB queries, inspect, profile |
| `diagram.py` | Generate diagrams | Mermaid, Graphviz, charts |
| `pdf.py` | Generate PDFs | Reports, exports |

## Model Tiers (used by llm.py)

| `--model` | Model | Use case |
|-----------|-------|----------|
| `fast` | llama3.2:3b | Classification, yes/no, tagging |
| `default` | llama3.1:8b | Summarize, explain, draft |
| `deep` | llama3.1:70b | Deep analysis, reasoning |
| `code` | deepseek-coder-v2:16b | Code review |
| `extract` | mistral:7b | Structured JSON extraction |
| `embed` | nomic-embed-text | Embeddings |

## Invocation

```bash
# Global sidecar
uv run --directory ~/.claude/sidecar python fetch.py <url>
uv run --directory ~/.claude/sidecar python llm.py summarize <file>
uv run --directory ~/.claude/sidecar python data.py inspect <file>
uv run --directory ~/.claude/sidecar python diagram.py mermaid <spec>
uv run --directory ~/.claude/sidecar python pdf.py render <file>

# Per-repo sidecar (check _sidecar/ first, fall back to global)
uv run --directory _sidecar python <script>.py
```

## Privacy Note

For any task involving confidential data (client info, contracts, access logs), always use `llm.py` with local Ollama models. Never pipe sensitive content to external APIs.
