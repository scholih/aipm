# Building the Reflex BV GenAI Installer

## What You Get

A single `ReflexGenAI-Setup.exe` that:
1. Shows a persona selection dialog (radio buttons for 8 roles)
2. Shows component checkboxes (pre-selected based on persona)
3. Installs everything in order: Chocolatey → Git → Python → uv → Node.js → Ollama → models → Obsidian → Claude Code → Beads
4. Configures the selected persona's CLAUDE.md
5. Creates the Obsidian vault with templates
6. Sets up the Python sidecar environment

## Prerequisites (Build Machine)

You need a **Windows machine** to compile the installer.

### Install Inno Setup

```powershell
# Option A: winget
winget install JRSoftware.InnoSetup

# Option B: Chocolatey
choco install innosetup -y

# Option C: Direct download
# https://jrsoftware.org/isdl.php
```

### Clone the Repo

```powershell
git clone https://github.com/scholih/aipm.git
cd aipm\reflex-genai\setup
```

## Compile

### Option A: GUI

1. Open Inno Setup Compiler (Start Menu → Inno Setup 6 → Inno Setup Compiler)
2. File → Open → select `installer.iss`
3. Build → Compile (or press Ctrl+F9)
4. Output: `setup\Output\ReflexGenAI-Setup.exe`

### Option B: Command Line

```powershell
# Inno Setup command-line compiler
iscc installer.iss

# Output: Output\ReflexGenAI-Setup.exe
```

## Installation Flow

When a user runs `ReflexGenAI-Setup.exe`:

```
Welcome → Persona Selection → Component Selection → Install → Done
                 │                      │
                 │                      └── Pre-checked based on persona:
                 │                          Developer: everything
                 │                          CEO: Ollama base only, no Graphviz/Tesseract
                 │                          etc.
                 │
                 └── 8 radio buttons, one per role
```

### Installation Order

| Step | Tool | Method | Why This Order |
|------|------|--------|----------------|
| 1 | Chocolatey | PowerShell bootstrap | Package manager — needed to install everything else |
| 2 | Git | `choco install git` | Needed for Obsidian vault and repo cloning |
| 3 | Python 3.12 | `choco install python312` | Required by uv and sidecar |
| 4 | uv | PowerShell installer | Python package manager for sidecar |
| 5 | Node.js LTS | `choco install nodejs-lts` | Required by Claude Code CLI and Beads |
| 6 | Ollama | `choco install ollama` | Local AI engine |
| 7 | Ollama models | `ollama pull ...` | Per-persona model selection |
| 8 | Obsidian | `choco install obsidian` | Knowledge base UI |
| 9 | Claude Code | `npm install -g` | AI assistant CLI |
| 10 | Beads | `npm install -g` | Issue tracker |
| 11 | Graphviz | `choco install graphviz` | Optional, for diagram generation |
| 12 | Tesseract | `choco install tesseract` | Optional, for OCR |
| 13 | Persona config | File copy | Merges shared + persona CLAUDE.md |
| 14 | Obsidian vault | `mkdir` + `git init` | Knowledge base structure |
| 15 | Sidecar setup | `uv init` + `uv add` | Python environment with dependencies |

## Customizing

### Adding a New Persona

1. Create folder: `personas/<name>/CLAUDE.md` + `PERSONA.md`
2. Add to `installer.iss` under `[Tasks]`:
   ```
   Name: "persona\new_role"; Description: "New Role — description"; Flags: exclusive
   ```
3. Add to `GetPersonaFolder()` function in `[Code]` section
4. Recompile

### Adding a New Component

1. Add to `[Components]` section in `installer.iss`
2. Add install logic in `CurStepChanged` procedure
3. Recompile

### Changing Ollama Models

Edit the model names in the `CurStepChanged` procedure. The models are pulled via `ollama pull <name>` — check https://ollama.com/library for available models.

## Testing

Before distributing:

1. **Test on a clean Windows 11 VM** — this is critical. The installer assumes nothing is pre-installed.
2. **Test each persona** — run the installer 8 times, once per persona, verify the right components are installed.
3. **Test skip logic** — verify that already-installed tools are detected and skipped.
4. **Test the sidecar** — after install, run:
   ```powershell
   sidecar llm.py summarize some-file.txt
   ```
5. **Test Claude Code** — open a terminal, run `claude`, verify the persona CLAUDE.md is loaded.

## Known Limitations

- **Ollama model pulls can take 10-30+ minutes** depending on network speed and model size. The installer shows progress but the user needs patience.
- **The 70b model needs 48GB+ RAM.** The installer doesn't check available RAM — add a warning or skip for machines with less.
- **Admin rights required** for Chocolatey installation. If corporate policy blocks this, use the manual `INSTALL.md` guide instead.
- **This installer was designed on macOS and is untested.** Alex: please validate and fix before distributing.

## Distributing

### Option A: Network Share
Place `ReflexGenAI-Setup.exe` on a shared drive. Users double-click to install.

### Option B: Email / Teams
The .exe is self-contained (~5MB without bundled models). Send it directly.

### Option C: Group Policy (GPO)
Inno Setup .exe can run silently:
```powershell
ReflexGenAI-Setup.exe /VERYSILENT /TASKS="persona\helpdesk,vault,shortcuts"
```
This enables IT to deploy specific personas via Group Policy without user interaction.

### Silent Install Task Names

```
persona\tech_subject_expert
persona\tech_solution_architect
persona\tech_developer
persona\tester
persona\helpdesk
persona\marketing
persona\ceo
persona\cto
vault
shortcuts
```

Example silent deploy for all helpdesk staff:
```powershell
ReflexGenAI-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /TASKS="persona\helpdesk,vault,shortcuts" /LOG="install.log"
```
