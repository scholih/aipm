# Knowledge Base Architecture — Reflex BV GenAI Environment

## Overview

A hybrid system combining Obsidian (structured knowledge) with SharePoint (collaboration), connected by local AI embeddings and automation. Total additional cost: $0.

---

## 1. Obsidian Vault (The Brain)

Shared git repo synced via OneDrive or a network share (cheapest option for a Windows environment).

### Vault Structure

```
reflex-kb/
├── products/          # Product documentation
├── integrations/      # Integration guides
├── hardware/          # Access control, visitor mgmt hardware
├── decisions/         # Architecture Decision Records (ADRs)
├── evaluations/       # Tech evaluations and comparisons
├── marketing/         # Brand guidelines, content templates
├── support/           # KB articles, common issues
├── strategy/          # Company strategy, roadmaps
└── templates/         # Note templates per persona
```

### Required Plugins (all free)

| Plugin | Purpose |
|--------|---------|
| Obsidian Git | Sync vault via git (auto-commit, pull, push) |
| Dataview | Query notes as a database (tables, lists, task views) |
| Templater | Persona-specific templates with dynamic fields |
| Smart Connections | Local AI-powered semantic linking using Ollama embeddings |
| Kanban | Visual boards for project and task tracking |

### Smart Connections Configuration

- **Embedding model:** Ollama with `nomic-embed-text`
- **Endpoint:** `http://localhost:11434`
- **Privacy:** All embeddings computed locally, nothing leaves the machine
- **Setup:** Smart Connections settings > Embedding model > Ollama > nomic-embed-text

### Persona Dashboards

Each persona has a "home" dashboard note (e.g., `HOME - Tech Expert.md`) that links to their relevant vault sections, pinned queries via Dataview, and current focus areas.

---

## 2. SharePoint (The Handshake)

Uses existing Microsoft 365 licensing. No additional cost.

### What Lives in SharePoint

- Shared documents requiring co-editing (Word, Excel, PowerPoint)
- Team channels and communication (Teams)
- Company-wide announcements and policies
- Client-facing deliverables

### Structure

Mirror the Obsidian vault folder structure where practical so content is easy to locate regardless of which system someone enters from.

### Copilot Integration

Microsoft Copilot natively indexes and searches SharePoint content. No additional configuration needed for search and summarization within the M365 ecosystem.

---

## 3. The Glue

### Obsidian Smart Connections

Indexes all vault content with local embeddings via Ollama. Enables semantic search across the entire knowledge base without external API calls.

### SharePoint to Obsidian Sync

Weekly automated export of key SharePoint documents to markdown in the Obsidian vault:
- Use Power Automate (included with M365, free)
- Flow: SharePoint modified docs > convert to markdown > commit to vault repo
- Keeps Obsidian as the single semantic search surface

### Beads Integration

Beads issue descriptions link to relevant Obsidian notes using `[[note]]` wiki-link syntax. This creates bidirectional traceability between tasks and knowledge.

### Per-Persona CLAUDE.md

Each persona's CLAUDE.md includes paths to their relevant KB sections, ensuring Claude Code always knows where to find domain-specific context.

---

## 4. Cost Analysis

| Component | Cost |
|-----------|------|
| Obsidian | Free |
| Obsidian plugins (Git, Dataview, Templater, Smart Connections, Kanban) | Free / open source |
| Ollama + nomic-embed-text | Free (runs locally) |
| SharePoint | Already licensed (M365) |
| Power Automate | Included with M365 |
| **Total additional cost** | **$0** |
