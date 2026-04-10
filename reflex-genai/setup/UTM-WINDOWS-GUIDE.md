# Building & Testing the Installer on macOS via UTM

You already have UTM installed with a Windows VM (`Windows.utm`). This guide covers how to use it to compile the Inno Setup installer and test the full GenAI environment setup.

## Starting Your Existing Windows VM

1. Open **UTM** from Applications
2. Select **Windows** in the sidebar
3. Click the **Play** button (▶)
4. Wait for Windows to boot (first boot after a while may take a minute)

> **Tip:** If the VM doesn't boot or shows "Display output is not active", try:
> - Right-click the VM → Edit → Display → change to "virtio-gpu" or "virtio-ramfb"
> - Allocate more RAM if it's sluggish (Edit → System → Memory → at least 8GB)
> - Allocate more CPU cores (Edit → System → CPU → 4+ cores)

## Recommended VM Settings for This Work

Since we're pulling Ollama models (potentially 60GB+) and compiling software, bump the resources:

| Setting | Minimum | Recommended |
|---------|---------|-------------|
| RAM | 4 GB | 8 GB |
| CPU Cores | 2 | 4 |
| Disk | 64 GB | 128 GB (models are large) |

To change: UTM → right-click VM → **Edit** → **System** tab.

> **Tip:** If your disk is too small, you can resize it:
> UTM → right-click VM → **Edit** → **Drives** → select the main drive → increase size.
> Then inside Windows: Disk Management → right-click C: → Extend Volume.

## Setting Up Shared Folders

The easiest way to get the repo files into the VM:

### Option A: Shared Folder (Recommended)

1. In UTM: right-click VM → **Edit** → **Sharing**
2. Enable **Directory Sharing**
3. Add path: `/Users/hjscholing/demos/aipm`
4. Boot the VM
5. In Windows, the shared folder appears as a network drive or under `\\Mac\aipm`

> **Tip:** If shared folders don't appear, install SPICE Guest Tools inside Windows:
> Download from https://www.spice-space.org/download/windows/spice-guest-tools/

### Option B: Git Clone Inside the VM

If shared folders are finicky, just clone from GitHub inside the VM:

```powershell
# Inside Windows VM — open PowerShell
winget install Git.Git
git clone https://github.com/scholih/aipm.git
cd aipm\reflex-genai\setup
```

This is actually the better test — it's exactly what Alex will do.

## Step 1: Install Inno Setup in the VM

```powershell
# Inside Windows VM
winget install JRSoftware.InnoSetup --accept-source-agreements --accept-package-agreements
```

Or download from https://jrsoftware.org/isdl.php

## Step 2: Compile the Installer

### GUI Method
1. Open **Inno Setup Compiler** from Start Menu
2. File → Open → navigate to `aipm\reflex-genai\setup\installer.iss`
3. Press **Ctrl+F9** (or Build → Compile)
4. Output: `aipm\reflex-genai\setup\Output\ReflexGenAI-Setup.exe`

### Command Line Method
```powershell
cd C:\Users\<you>\aipm\reflex-genai\setup
& "C:\Program Files (x86)\Inno Setup 6\iscc.exe" installer.iss
```

## Step 3: Test the Installer

### Snapshot First!

**Before running the installer**, create a VM snapshot so you can reset and test again:

1. In UTM: right-click VM → **Snapshots** → **Take Snapshot**
2. Name it "Pre-install clean state"

Now you can install, test, restore snapshot, and repeat.

### Run the Installer

1. Double-click `ReflexGenAI-Setup.exe`
2. Walk through the wizard:
   - Select a persona (try **Tech Developer** first — it installs everything)
   - Leave all components checked
   - Click Install
3. Watch the progress — this will take 15-30 minutes (Ollama model downloads)

### Verify After Install

Open a **new PowerShell window** (important — PATH needs to refresh):

```powershell
# Check all tools are installed
python --version          # Python 3.12.x
uv --version              # uv 0.x.x
node --version             # v20.x.x or v22.x.x
git --version              # git 2.x.x
ollama --version           # ollama 0.x.x
claude --version           # Claude Code x.x.x
bd --version               # Beads x.x.x

# Check Ollama models
ollama list                # Should show pulled models

# Check persona config
cat ~/.claude/CLAUDE.md    # Should show shared + persona config

# Check sidecar
sidecar llm.py --help      # Should show usage (if shortcut was installed)
# Or:
uv run --directory "$env:USERPROFILE\.claude\sidecar" python -c "print('OK')"

# Check Obsidian vault
ls ~/reflex-kb/            # Should show folder structure
```

### Test Each Persona

After testing Developer, restore the snapshot and test at least:
- **Helpdesk** (minimal install — should be fast)
- **CEO** (minimal + different component selection)
- **CTO** (full install like developer but different config)

## Troubleshooting

| Problem | Fix |
|---------|-----|
| VM won't boot | Edit → System → check UEFI boot is enabled |
| Very slow | Increase RAM to 8GB, CPU to 4 cores |
| No internet in VM | Edit → Network → make sure "Shared Network" is selected |
| Shared folder not visible | Install SPICE Guest Tools, reboot VM |
| Inno Setup won't compile | Check paths in .iss file are relative, not absolute |
| Chocolatey install hangs | May need to run PowerShell as Administrator manually first |
| Ollama pull fails | Check VM has internet; might be DNS issue → try `8.8.8.8` as DNS |
| "Not enough disk space" | Resize VM disk (UTM → Edit → Drives), then extend in Windows |

## Workflow Summary

```
Mac (your machine)
  │
  ├── Edit installer.iss in your editor
  │
  ├── git commit + push
  │
  └── UTM Windows VM
        │
        ├── git pull (gets latest changes)
        ├── iscc installer.iss (compile)
        ├── Run ReflexGenAI-Setup.exe (test)
        ├── Restore snapshot (reset)
        └── Repeat
```

## Getting the .exe Out of the VM

Once the installer is tested and working:

### Option A: Shared Folder
If you set up directory sharing, the compiled .exe is already visible on your Mac.

### Option B: Copy via Git
```powershell
# Inside VM — add .exe to repo (temporary, for transfer)
git add -f setup/Output/ReflexGenAI-Setup.exe
git commit -m "build: compiled installer for testing"
git push
```

Then on your Mac:
```bash
git pull
# Grab the .exe, then remove it from git (don't keep binaries in repo)
cp reflex-genai/setup/Output/ReflexGenAI-Setup.exe ~/Desktop/
git rm reflex-genai/setup/Output/ReflexGenAI-Setup.exe
git commit -m "chore: remove binary from repo"
```

### Option C: GitHub Release
Better for distribution — upload the .exe as a GitHub Release artifact:
```powershell
# Inside VM
gh release create v0.1.0 setup\Output\ReflexGenAI-Setup.exe --title "v0.1.0 - Initial installer" --notes "Untested draft. Validate before distributing."
```
