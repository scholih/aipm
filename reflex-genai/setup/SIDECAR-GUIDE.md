# Python Sidecar — What It Is, Why You Need It, and How to Set It Up

## What is the Sidecar?

The "sidecar" is a small collection of Python scripts that run **alongside** your AI assistant (Claude, Copilot). Think of it like a toolbox that sits next to your main tool — it doesn't replace anything, it makes things faster and cheaper.

### The Problem It Solves

When you ask Claude or Copilot to summarize a document, fetch a webpage, or analyze data, the AI does everything in its own context window. That means:

- **Expensive** — every token of input/output costs money on the Claude API
- **Slow** — the AI reads the whole document even if you only need a summary
- **Limited** — the AI can't browse the web, run database queries, or generate diagrams natively

The sidecar offloads these tasks to small, fast Python scripts that run **locally on your laptop**. Many of them use **Ollama** (free, local AI) instead of the Claude API, saving costs while keeping data private.

### Real Examples

| Without Sidecar | With Sidecar | Savings |
|-----------------|-------------|---------|
| Ask Claude to read a 50-page PDF and summarize it | `llm.py summarize report.pdf` runs locally via Ollama | ~$0.50 per document |
| Ask Claude to fetch a competitor's website | `fetch.py https://competitor.com` grabs it locally | ~$0.10 per page |
| Ask Claude to create an architecture diagram | `diagram.py mermaid spec.json` generates SVG locally | ~$0.20 per diagram |
| Ask Claude to query a data file | `data.py query "SELECT * FROM sales.csv LIMIT 10"` | ~$0.30 per query |

Over a team of 8 people doing this daily, costs add up fast. The sidecar keeps them near zero.

### How It Fits in the Windows Landscape

```
┌─────────────────────────────────────────────────────┐
│                   Your Windows Laptop                │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │  Claude Code  │  │   Copilot    │  │  Obsidian  │ │
│  │   (terminal)  │  │  (browser)   │  │   (notes)  │ │
│  └──────┬───────┘  └──────────────┘  └────────────┘ │
│         │                                            │
│         │  calls sidecar scripts                     │
│         ▼                                            │
│  ┌──────────────────────────────────┐                │
│  │        Python Sidecar            │                │
│  │  fetch.py  llm.py  data.py       │                │
│  │  diagram.py  pdf.py              │                │
│  └──────────┬───────────────────────┘                │
│             │                                        │
│             │  uses for AI tasks                     │
│             ▼                                        │
│  ┌──────────────────────────────────┐                │
│  │     Ollama (local AI engine)     │                │
│  │  Free · Private · No internet    │                │
│  └──────────────────────────────────┘                │
└──────────────────────────────────────────────────────┘
```

**Key point:** The sidecar is NOT a separate application you open. It's scripts that Claude Code calls automatically when configured in your persona. You don't interact with them directly — Claude does.

---

## Installation Guide

### Option A: Automated (Recommended)

If you already ran `install.ps1`, Python and uv are installed. Skip to [Step 3: Set Up the Sidecar](#step-3-set-up-the-sidecar).

### Option B: Manual Installation

#### Step 1: Install a Package Manager

Windows has two main package managers. Pick one:

##### Chocolatey (older, larger ecosystem)

```powershell
# Run PowerShell as Administrator
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

After install, restart your terminal. Verify:
```powershell
choco --version
# Expected: 2.x.x
```

##### winget (built into Windows 11)

Already installed on Windows 11. Verify:
```powershell
winget --version
# Expected: v1.x.xxxx
```

> **Which one?** Use **winget** if you're on Windows 11 — it's built-in and Microsoft-supported. Use **Chocolatey** if you need packages that winget doesn't have, or if your IT department already uses it.

#### Step 2: Install Python and uv

##### What is uv?

`uv` is a modern Python package manager that replaces `pip`, `virtualenv`, and `pipenv`. It:
- Automatically manages virtual environments (no `activate` / `deactivate`)
- Is 10-100x faster than pip
- Works the same on Windows, Mac, and Linux
- Handles Python version management too

Think of it as "npm for Python" — one tool that does everything.

##### Install Python

**With winget:**
```powershell
winget install Python.Python.3.12
```

**With Chocolatey:**
```powershell
choco install python312 -y
```

**Verify:**
```powershell
python --version
# Expected: Python 3.12.x
```

> **Tip:** If `python` doesn't work but `python3` does, run:
> ```powershell
> # Create an alias (add to your PowerShell profile for persistence)
> Set-Alias python python3
> ```

> **Tip:** If Python isn't found at all after install, restart your terminal. Windows needs to refresh the PATH.

##### Install uv

**Recommended method (works everywhere):**
```powershell
irm https://astral.sh/uv/install.ps1 | iex
```

**With winget:**
```powershell
winget install astral-sh.uv
```

**With Chocolatey:**
```powershell
choco install uv -y
```

**With pip (if you already have Python):**
```powershell
pip install uv
```

**Verify:**
```powershell
uv --version
# Expected: uv 0.x.x
```

> **Tip:** After installing uv, you almost never need `pip` again. Use `uv add` instead of `pip install`, and `uv run` instead of `python`.

#### Step 3: Set Up the Sidecar

##### Create the sidecar directory

```powershell
# Create the directory
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude\sidecar" -Force

# Navigate to it
cd "$env:USERPROFILE\.claude\sidecar"
```

##### Initialize the Python project

```powershell
uv init
```

This creates a `pyproject.toml` file — the project manifest.

##### Install dependencies

```powershell
# Web fetching
uv add httpx beautifulsoup4 lxml

# LLM integration (Ollama client)
uv add ollama

# Data analysis
uv add duckdb pandas

# Diagram generation
uv add graphviz

# PDF generation (optional)
uv add weasyprint
```

> **Tip:** If a package fails to install, it's usually a missing system dependency. Common fixes:
> ```powershell
> # For graphviz: install the system package first
> winget install Graphviz.Graphviz
> # Then retry: uv add graphviz
>
> # For weasyprint: needs GTK3 runtime
> # Download from https://github.com/nickvdyck/weasyprint-win/releases
> ```

##### Copy sidecar scripts

The sidecar scripts are provided in the shared config. Copy them:

```powershell
# From the reflex-genai repo
Copy-Item "path\to\reflex-genai\shared\sidecar\*" "$env:USERPROFILE\.claude\sidecar\" -Recurse -Force
```

##### Verify the setup

```powershell
# Test that uv run works
uv run --directory "$env:USERPROFILE\.claude\sidecar" python -c "print('Sidecar OK')"

# Test Ollama connection (Ollama must be running)
uv run --directory "$env:USERPROFILE\.claude\sidecar" python -c "import ollama; print(ollama.list())"
```

#### Step 4: Install Ollama

Ollama runs AI models locally on your laptop — free, private, no internet needed.

**With winget:**
```powershell
winget install Ollama.Ollama
```

**With Chocolatey:**
```powershell
choco install ollama -y
```

**Manual:** Download from https://ollama.com/download/windows

After install, Ollama runs as a background service automatically.

##### Pull the models your persona needs

```powershell
# Base models (everyone needs these)
ollama pull llama3.2:3b          # Fast: tagging, yes/no, classification
ollama pull llama3.1:8b          # Default: summaries, drafting, explanations
ollama pull mistral:7b           # Extract: structured JSON extraction
ollama pull nomic-embed-text     # Embeddings: for Obsidian Smart Connections

# Technical personas only (Developer, Solution Architect, CTO)
ollama pull deepseek-coder-v2:16b   # Code: code review, generation
ollama pull llama3.1:70b            # Deep: complex analysis (needs 48GB+ RAM)
```

> **Tip:** The 70b model requires significant RAM. If your laptop has less than 48GB RAM, skip it — the 8b model handles most tasks well.

> **Tip:** Models are stored in `C:\Users\<you>\.ollama\models\`. They can be large (4-40GB each). Make sure you have disk space.

> **Tip:** To check which models you have:
> ```powershell
> ollama list
> ```

> **Tip:** To test a model works:
> ```powershell
> ollama run llama3.1:8b "Say hello in one sentence"
> ```

---

## How to Use the Sidecar

### You usually don't call it directly

When Claude Code is configured with your persona, it calls sidecar scripts automatically. For example, if you ask Claude to "summarize this document," it will run `llm.py summarize doc.pdf` behind the scenes instead of reading the entire document into its context.

### But you can, if you want to

```powershell
# Fetch a webpage
uv run --directory "$env:USERPROFILE\.claude\sidecar" python fetch.py https://example.com

# Summarize a file with local AI
uv run --directory "$env:USERPROFILE\.claude\sidecar" python llm.py summarize report.pdf

# Extract structured data
uv run --directory "$env:USERPROFILE\.claude\sidecar" python llm.py extract data.txt --schema "name,email,role"

# Query a CSV/Excel file
uv run --directory "$env:USERPROFILE\.claude\sidecar" python data.py query "SELECT * FROM sales.xlsx LIMIT 10"

# Generate a diagram
uv run --directory "$env:USERPROFILE\.claude\sidecar" python diagram.py mermaid flowchart.json
```

> **Tip:** That `uv run --directory ...` prefix is long. Create a shortcut:
> ```powershell
> # Add to your PowerShell profile ($PROFILE)
> function sidecar { uv run --directory "$env:USERPROFILE\.claude\sidecar" python @args }
>
> # Now you can just do:
> sidecar fetch.py https://example.com
> sidecar llm.py summarize report.pdf
> ```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `python` not found | PATH not updated after install | Restart terminal, or run `refreshenv` (Chocolatey) |
| `uv` not found | PATH not updated | Restart terminal |
| `ollama` not found | Service not started | Start Ollama from Start Menu, or `ollama serve` |
| `uv add` fails with build error | Missing system library | Install the system package first (see package-specific tips above) |
| `ollama pull` hangs | Firewall blocking download | Check corporate proxy settings, try direct download |
| Model runs very slowly | Not enough RAM | Use a smaller model (`llama3.2:3b` instead of `llama3.1:8b`) |
| `Import Error: ollama` | Package not installed in sidecar | `cd ~/.claude/sidecar && uv add ollama` |
| Scripts work in terminal but not in Claude Code | Different Python/PATH | Make sure `uv` is in system PATH, not just user PATH |

### Checking your setup

Run this to verify everything works:

```powershell
Write-Host "=== Sidecar Health Check ===" -ForegroundColor Cyan

# Python
Write-Host -NoNewline "Python: "; python --version

# uv
Write-Host -NoNewline "uv: "; uv --version

# Ollama
Write-Host -NoNewline "Ollama: "; ollama --version

# Models
Write-Host "Models:"
ollama list

# Sidecar
Write-Host -NoNewline "Sidecar: "
uv run --directory "$env:USERPROFILE\.claude\sidecar" python -c "print('OK')"
```

---

## FAQ

**Q: Do I need to know Python?**
A: No. The sidecar scripts are pre-built tools. You don't write Python — you run scripts. It's like using `git` without knowing C.

**Q: Is my data safe?**
A: Yes. Ollama runs 100% locally. Your data never leaves your laptop. The sidecar scripts connect to Ollama at `localhost:11434` — no internet needed for AI tasks.

**Q: What if I already have Python installed?**
A: That's fine. `uv` manages its own virtual environments and won't interfere with your existing Python setup.

**Q: Can I use Chocolatey AND winget?**
A: Yes, they coexist fine. Just pick one for each package to avoid confusion about updates. Our recommendation: use winget for Microsoft-ecosystem tools (Python, Git, Node.js) and Chocolatey for everything else if needed.

**Q: How much disk space do I need?**
A: Base models (3b + 8b + 7b + embeddings): ~12GB. With code model: +9GB. With 70b model: +40GB. The sidecar scripts themselves are <1MB.

**Q: The 70b model is too slow on my laptop. What do I do?**
A: Remove it (`ollama rm llama3.1:70b`) and stick with the 8b model. It handles 90% of tasks. Only the Solution Architect and CTO personas benefit from the 70b model for complex strategic analysis.
