#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reflex BV GenAI Environment Setup
.DESCRIPTION
    Installs all prerequisites for the Reflex BV GenAI persona environments.
    Run as Administrator on Windows 11.
.PARAMETER Persona
    Optional. One of: tech-subject-expert, tech-solution-architect, tech-developer,
    tester, helpdesk, marketing, ceo, cto. If omitted, installs shared components only.
.PARAMETER SkipOllama
    Skip Ollama installation (if already installed).
.PARAMETER VaultPath
    Path for shared Obsidian vault. Default: ~/reflex-kb
#>
param(
    [string]$Persona,
    [switch]$SkipOllama,
    [string]$VaultPath = "$env:USERPROFILE\reflex-kb"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Reflex BV GenAI Environment Setup ===" -ForegroundColor Cyan
Write-Host ""

# --- Prerequisites ---
Write-Host "[1/7] Checking prerequisites..." -ForegroundColor Yellow

$prerequisites = @(
    @{ Name = "Git"; Check = { git --version }; Install = "winget install Git.Git --accept-source-agreements --accept-package-agreements" },
    @{ Name = "Node.js"; Check = { node --version }; Install = "winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements" },
    @{ Name = "Python"; Check = { python --version }; Install = "winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements" }
)

foreach ($prereq in $prerequisites) {
    try {
        & $prereq.Check | Out-Null
        Write-Host "  [OK] $($prereq.Name) already installed" -ForegroundColor Green
    } catch {
        Write-Host "  [INSTALLING] $($prereq.Name)..." -ForegroundColor Yellow
        Invoke-Expression $prereq.Install
    }
}

# --- Ollama ---
Write-Host "[2/7] Setting up Ollama..." -ForegroundColor Yellow

if (-not $SkipOllama) {
    try {
        ollama --version | Out-Null
        Write-Host "  [OK] Ollama already installed" -ForegroundColor Green
    } catch {
        Write-Host "  [INSTALLING] Ollama..." -ForegroundColor Yellow
        winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements
    }

    Write-Host "  Pulling models (this may take a while)..." -ForegroundColor Yellow
    $models = @(
        "llama3.2:3b",        # fast - classification, tagging
        "llama3.1:8b",        # default - summarize, draft
        "mistral:7b",         # extract - structured JSON
        "nomic-embed-text"    # embeddings for Obsidian Smart Connections
    )

    # Optional heavy models based on persona
    $heavyPersonas = @("tech-solution-architect", "tech-developer", "cto")
    if ($Persona -in $heavyPersonas) {
        $models += "llama3.1:70b"          # deep - complex analysis
        $models += "deepseek-coder-v2:16b" # code - code review
    }

    foreach ($model in $models) {
        Write-Host "  Pulling $model..." -ForegroundColor Gray
        ollama pull $model
    }
} else {
    Write-Host "  [SKIPPED] Ollama installation" -ForegroundColor Gray
}

# --- uv (Python package manager) ---
Write-Host "[3/7] Installing uv..." -ForegroundColor Yellow
try {
    uv --version | Out-Null
    Write-Host "  [OK] uv already installed" -ForegroundColor Green
} catch {
    irm https://astral.sh/uv/install.ps1 | iex
}

# --- Claude Code ---
Write-Host "[4/7] Installing Claude Code CLI..." -ForegroundColor Yellow
try {
    claude --version | Out-Null
    Write-Host "  [OK] Claude Code already installed" -ForegroundColor Green
} catch {
    npm install -g @anthropic-ai/claude-code
}

# --- Beads ---
Write-Host "[5/7] Installing Beads..." -ForegroundColor Yellow
try {
    bd --version | Out-Null
    Write-Host "  [OK] Beads already installed" -ForegroundColor Green
} catch {
    npm install -g @beads/bd
}

# --- Obsidian ---
Write-Host "[6/7] Setting up Obsidian vault..." -ForegroundColor Yellow
try {
    $obsidianInstalled = Get-Command obsidian -ErrorAction SilentlyContinue
    if (-not $obsidianInstalled) {
        winget install Obsidian.Obsidian --accept-source-agreements --accept-package-agreements
    }
    Write-Host "  [OK] Obsidian installed" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Install Obsidian manually from https://obsidian.md" -ForegroundColor Yellow
}

# Create vault structure if it doesn't exist
if (-not (Test-Path $VaultPath)) {
    Write-Host "  Creating vault at $VaultPath..." -ForegroundColor Gray
    $folders = @(
        "products", "integrations", "hardware", "decisions",
        "evaluations", "marketing", "support", "strategy", "templates"
    )
    foreach ($folder in $folders) {
        New-Item -ItemType Directory -Path "$VaultPath\$folder" -Force | Out-Null
    }

    # Copy templates
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $templateDir = Join-Path (Split-Path -Parent $scriptDir) "knowledge-base\obsidian\templates"
    if (Test-Path $templateDir) {
        Copy-Item "$templateDir\*" "$VaultPath\templates\" -Force
    }

    # Initialize git
    Push-Location $VaultPath
    git init
    git add .
    git commit -m "init: initialize Reflex BV knowledge base"
    Pop-Location

    Write-Host "  [OK] Vault created at $VaultPath" -ForegroundColor Green
} else {
    Write-Host "  [OK] Vault already exists at $VaultPath" -ForegroundColor Green
}

# --- Persona Setup ---
Write-Host "[7/7] Configuring persona..." -ForegroundColor Yellow

if ($Persona) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $personaDir = Join-Path (Split-Path -Parent $scriptDir) "personas\$Persona"

    if (-not (Test-Path $personaDir)) {
        Write-Host "  [ERROR] Unknown persona: $Persona" -ForegroundColor Red
        Write-Host "  Available: tech-subject-expert, tech-solution-architect, tech-developer, tester, helpdesk, marketing, ceo, cto" -ForegroundColor Gray
        exit 1
    }

    # Create Claude config directory
    $claudeDir = "$env:USERPROFILE\.claude"
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    # Copy shared CLAUDE.md as base, append persona-specific config
    $sharedConfig = Join-Path (Split-Path -Parent $scriptDir) "shared\CLAUDE.md"
    $personaConfig = Join-Path $personaDir "CLAUDE.md"

    $combined = ""
    if (Test-Path $sharedConfig) {
        $combined += Get-Content $sharedConfig -Raw
        $combined += "`n`n# --- Persona-Specific Configuration ---`n`n"
    }
    if (Test-Path $personaConfig) {
        $combined += Get-Content $personaConfig -Raw
    }

    Set-Content -Path "$claudeDir\CLAUDE.md" -Value $combined
    Write-Host "  [OK] Persona '$Persona' configured" -ForegroundColor Green

    # Install Claude Code plugins based on persona
    $needsSerena = @("tech-subject-expert", "tech-solution-architect", "tech-developer", "cto")
    $needsSuperpowers = @("tech-subject-expert", "tech-solution-architect", "tech-developer", "cto", "marketing", "ceo")

    Write-Host ""
    Write-Host "  Next steps (run inside Claude Code):" -ForegroundColor Cyan
    Write-Host "    /plugin install beads@beads-marketplace" -ForegroundColor White

    if ($Persona -in $needsSerena) {
        Write-Host "    # Serena: run 'claude mcp add serena' in your project directory" -ForegroundColor White
    }
    if ($Persona -in $needsSuperpowers) {
        Write-Host "    /plugin marketplace add obra/superpowers-marketplace" -ForegroundColor White
        Write-Host "    /plugin install superpowers@superpowers-marketplace" -ForegroundColor White
    }
} else {
    Write-Host "  [SKIPPED] No persona specified. Run again with -Persona <name>" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Usage:" -ForegroundColor Cyan
Write-Host "  .\install.ps1 -Persona tech-developer     # Full setup for a developer"
Write-Host "  .\install.ps1 -Persona ceo -SkipOllama     # CEO setup, skip Ollama"
Write-Host "  .\install.ps1                               # Shared components only"
Write-Host ""
