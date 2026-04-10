# Reflex BV GenAI - Windows Installation Guide

## Prerequisites

- Windows 11 (22H2 or later)
- Administrator access
- Internet connection
- Git installed (`winget install Git.Git`)

## Step-by-Step Installation

### 1. Install Package Managers

```powershell
# Python package manager
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# Verify
uv --version
```

### 2. Install Node.js

```powershell
winget install OpenJS.NodeJS.LTS
# Restart terminal after install
node --version  # Should be 18+
```

### 3. Install Python

```powershell
uv python install 3.12
uv python list  # Verify 3.12 is available
```

### 4. Install Ollama

```powershell
winget install Ollama.Ollama
# Restart terminal, then pull models
```

### 5. Pull Ollama Models

Required for all personas:

```powershell
ollama pull llama3.2:3b        # fast tier - classification, tagging
ollama pull llama3.1:8b        # default tier - summarize, explain
ollama pull mistral:7b         # extract tier - structured JSON
ollama pull nomic-embed-text   # embeddings
```

For technical personas (Developer, Architect, CTO):

```powershell
ollama pull deepseek-coder-v2:16b  # code tier - code review
```

Optional (requires 48GB+ RAM):

```powershell
ollama pull llama3.1:70b       # deep tier - complex reasoning
```

### 6. Install Claude Code CLI

```powershell
npm install -g @anthropic-ai/claude-code
claude --version
```

Set your API key:

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
# Add to PowerShell profile for persistence:
Add-Content $PROFILE 'Set-Item -Path Env:ANTHROPIC_API_KEY -Value "sk-ant-..."'
```

### 7. Install Beads CLI

```powershell
npm install -g @beads/bd
bd --version
```

### 8. Install Obsidian

```powershell
winget install Obsidian.Obsidian
```

### 9. Configure Shared Vault

Set the shared vault location (choose one):

```powershell
# Option A: OneDrive (recommended for remote teams)
$vaultPath = "$env:OneDrive\Reflex-GenAI-Vault"

# Option B: Network share
$vaultPath = "\\fileserver\shared\genai-vault"
```

Open Obsidian and select "Open folder as vault" pointing to the shared location.

### 10. Per-Persona Setup

Copy the persona-specific CLAUDE.md:

```powershell
# Replace <persona> with: developer, architect, tester, helpdesk, marketing, ceo, cto, subject-expert
Copy-Item ".\personas\<persona>\CLAUDE.md" "$env:USERPROFILE\.claude\CLAUDE.md"
```

Install persona-specific sidecar tools:

```powershell
# Clone sidecar to user home
git clone <sidecar-repo-url> "$env:USERPROFILE\.claude\sidecar"

# Install dependencies
uv run --directory "$env:USERPROFILE\.claude\sidecar" python -c "print('sidecar ready')"
```

## Automated Setup Script

Save as `install.ps1` and run with administrator privileges:

```powershell
#Requires -RunAsAdministrator
param(
    [ValidateSet("developer","architect","tester","helpdesk","marketing","ceo","cto","subject-expert")]
    [string]$Persona = "developer"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Reflex BV GenAI Setup ===" -ForegroundColor Cyan
Write-Host "Persona: $Persona"

# Package managers and runtimes
Write-Host "`n[1/7] Installing uv..." -ForegroundColor Yellow
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

Write-Host "`n[2/7] Installing Node.js..." -ForegroundColor Yellow
winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements

Write-Host "`n[3/7] Installing Python 3.12..." -ForegroundColor Yellow
uv python install 3.12

# Ollama
Write-Host "`n[4/7] Installing Ollama and pulling models..." -ForegroundColor Yellow
winget install Ollama.Ollama --accept-package-agreements --accept-source-agreements
Start-Sleep -Seconds 5

$baseModels = @("llama3.2:3b", "llama3.1:8b", "mistral:7b", "nomic-embed-text")
$techModels = @("deepseek-coder-v2:16b")
$techPersonas = @("developer", "architect", "cto", "subject-expert")

foreach ($model in $baseModels) {
    Write-Host "  Pulling $model..."
    ollama pull $model
}

if ($techPersonas -contains $Persona) {
    foreach ($model in $techModels) {
        Write-Host "  Pulling $model..."
        ollama pull $model
    }
}

# CLI tools
Write-Host "`n[5/7] Installing Claude Code CLI..." -ForegroundColor Yellow
npm install -g @anthropic-ai/claude-code

Write-Host "`n[6/7] Installing Beads CLI..." -ForegroundColor Yellow
npm install -g @beads/bd

# Obsidian
Write-Host "`n[7/7] Installing Obsidian..." -ForegroundColor Yellow
winget install Obsidian.Obsidian --accept-package-agreements --accept-source-agreements

# Persona config
$claudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir | Out-Null }

$personaConfig = Join-Path $PSScriptRoot "..\personas\$Persona\CLAUDE.md"
if (Test-Path $personaConfig) {
    Copy-Item $personaConfig "$claudeDir\CLAUDE.md" -Force
    Write-Host "`nPersona config copied to $claudeDir\CLAUDE.md" -ForegroundColor Green
} else {
    Write-Host "`nWARNING: Persona config not found at $personaConfig" -ForegroundColor Red
    Write-Host "Copy your persona CLAUDE.md manually to $claudeDir\CLAUDE.md"
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host "Next steps:"
Write-Host "  1. Set ANTHROPIC_API_KEY in your PowerShell profile"
Write-Host "  2. Open Obsidian and configure shared vault"
Write-Host "  3. Run 'claude' to verify installation"
```

## Verification

After setup, verify all components:

```powershell
claude --version          # Claude Code CLI
bd --version              # Beads CLI
ollama list               # Installed models
uv --version              # Python package manager
node --version            # Node.js
python --version          # Python
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `ollama` not found | Restart terminal after install |
| Model pull fails | Check disk space (8B models need ~5GB each) |
| Claude auth error | Verify ANTHROPIC_API_KEY is set |
| uv not found | Restart terminal or check PATH |
| Obsidian vault sync conflicts | Use OneDrive conflict resolution, keep newest |
