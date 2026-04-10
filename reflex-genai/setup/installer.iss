; Reflex BV GenAI Environment Installer
; Compile with Inno Setup 6.x (https://jrsoftware.org/isinfo.php)
;
; IMPORTANT: This script must be compiled on a Windows machine with
; Inno Setup installed. It produces a single .exe installer.
;
; To compile:
;   1. Install Inno Setup: winget install JRSoftware.InnoSetup
;   2. Right-click this file → "Compile" (or open in Inno Setup Compiler)
;   3. Output: setup/Output/ReflexGenAI-Setup.exe

[Setup]
AppName=Reflex BV GenAI Environment
AppVersion=0.1.0
AppPublisher=Reflex BV
DefaultDirName={userappdata}\reflex-genai
DefaultGroupName=Reflex BV GenAI
OutputBaseFilename=ReflexGenAI-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
SetupIconFile=compiler:SetupClassicIcon.ico
DisableProgramGroupPage=yes
LicenseFile=
; Minimum Windows 11
MinVersion=10.0.22000

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"

; ============================================================
; Files to bundle into the installer
; ============================================================
[Files]
; Persona configurations
Source: "..\personas\*"; DestDir: "{app}\personas"; Flags: recursesubdirs createallsubdirs
; Shared configs
Source: "..\shared\*"; DestDir: "{app}\shared"; Flags: recursesubdirs createallsubdirs
; Knowledge base templates
Source: "..\knowledge-base\*"; DestDir: "{app}\knowledge-base"; Flags: recursesubdirs createallsubdirs
; Docs
Source: "..\README.md"; DestDir: "{app}"
Source: "INSTALL.md"; DestDir: "{app}\setup"
Source: "SIDECAR-GUIDE.md"; DestDir: "{app}\setup"
Source: "SIDECAR-DEVELOPMENT.md"; DestDir: "{app}\setup"
Source: "WHY-PYTHON.md"; DestDir: "{app}\setup"
; PowerShell helper (fallback)
Source: "install.ps1"; DestDir: "{app}\setup"

; ============================================================
; Custom Persona Selection Page
; ============================================================
[Types]
Name: "custom"; Description: "Choose your persona"; Flags: iscustom

[Components]
; Base components (always installed)
Name: "base"; Description: "Base tools (Chocolatey, Python, uv, Node.js, Git)"; Types: custom; Flags: fixed
Name: "ollama"; Description: "Ollama (local AI engine — free, private)"; Types: custom
Name: "ollama\base_models"; Description: "Base models: llama3.2:3b, llama3.1:8b, mistral:7b, nomic-embed-text (~12GB)"; Types: custom
Name: "ollama\code_models"; Description: "Code model: deepseek-coder-v2:16b (~9GB)"; Types: custom
Name: "ollama\deep_model"; Description: "Deep model: llama3.1:70b (~40GB, needs 48GB+ RAM)"; Types: custom
Name: "obsidian"; Description: "Obsidian (knowledge base)"; Types: custom
Name: "claude"; Description: "Claude Code CLI"; Types: custom
Name: "beads"; Description: "Beads issue tracker (bd)"; Types: custom
Name: "graphviz"; Description: "Graphviz (diagram generation)"; Types: custom
Name: "tesseract"; Description: "Tesseract OCR (text from images)"; Types: custom

; ============================================================
; Persona-based presets via Tasks
; ============================================================
[Tasks]
; Persona selection (radio buttons — mutually exclusive)
Name: "persona"; Description: "Select your role:"; GroupDescription: "Persona Configuration"; Flags: exclusive
Name: "persona\tech_subject_expert"; Description: "Tech Subject Expert — MS/Office, workplace tech, hardware evaluations"; Flags: exclusive
Name: "persona\tech_solution_architect"; Description: "Tech Solution Architect — system design, integrations, strategy"; Flags: exclusive
Name: "persona\tech_developer"; Description: "Tech Developer — GenAI-driven development, TDD, future-proof code"; Flags: exclusive
Name: "persona\tester"; Description: "Tester — test plans, QA frameworks, bug tracking (non-programmer)"; Flags: exclusive
Name: "persona\helpdesk"; Description: "Helpdesk — ticket management, knowledge base, customer support"; Flags: exclusive
Name: "persona\marketing"; Description: "Marketing Manager — content, campaigns, competitor analysis"; Flags: exclusive
Name: "persona\ceo"; Description: "CEO — strategic decisions, executive summaries, KPIs"; Flags: exclusive
Name: "persona\cto"; Description: "CTO — technical strategy, architecture oversight, roadmaps"; Flags: exclusive

; Additional options
Name: "vault"; Description: "Create shared Obsidian vault at ~/reflex-kb"; GroupDescription: "Knowledge Base"
Name: "shortcuts"; Description: "Add PowerShell sidecar shortcut to profile"; GroupDescription: "Convenience"

; ============================================================
; Registry entries for uninstall info
; ============================================================
[Registry]
Root: HKCU; Subkey: "Software\ReflexBV\GenAI"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"
Root: HKCU; Subkey: "Software\ReflexBV\GenAI"; ValueType: string; ValueName: "Version"; ValueData: "0.1.0"

; ============================================================
; Installation logic (Pascal Script)
; ============================================================
[Code]
var
  PersonaPage: TInputOptionWizardPage;
  StatusLabel: TNewStaticText;
  SelectedPersona: String;

// Map persona selection to folder name
function GetPersonaFolder(): String;
begin
  if IsTaskSelected('persona\tech_subject_expert') then Result := 'tech-subject-expert'
  else if IsTaskSelected('persona\tech_solution_architect') then Result := 'tech-solution-architect'
  else if IsTaskSelected('persona\tech_developer') then Result := 'tech-developer'
  else if IsTaskSelected('persona\tester') then Result := 'tester'
  else if IsTaskSelected('persona\helpdesk') then Result := 'helpdesk'
  else if IsTaskSelected('persona\marketing') then Result := 'marketing'
  else if IsTaskSelected('persona\ceo') then Result := 'ceo'
  else if IsTaskSelected('persona\cto') then Result := 'cto'
  else Result := 'tech-developer'; // default
end;

// Run a command and wait for completion
function RunAndWait(const Cmd, Params: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(Cmd, Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
  if not Result then
    Log('Failed to run: ' + Cmd + ' ' + Params);
end;

// Run PowerShell command
function RunPowerShell(const Command: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -Command "' + Command + '"',
    '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
end;

// Check if a command exists
function CommandExists(const Cmd: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec('where.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
    and (ResultCode = 0);
end;

// ============================================================
// Main installation procedure
// ============================================================
procedure CurStepChanged(CurStep: TSetupStep);
var
  PersonaFolder: String;
  ClaudeDir: String;
  VaultPath: String;
  SharedConfig: String;
  PersonaConfig: String;
  CombinedConfig: String;
begin
  if CurStep = ssPostInstall then
  begin
    PersonaFolder := GetPersonaFolder();
    ClaudeDir := ExpandConstant('{userprofile}') + '\.claude';
    VaultPath := ExpandConstant('{userprofile}') + '\reflex-kb';

    // --------------------------------------------------------
    // Step 1: Install Chocolatey (if not present)
    // --------------------------------------------------------
    WizardForm.StatusLabel.Caption := 'Installing Chocolatey...';
    if not CommandExists('choco') then
    begin
      RunPowerShell(
        'Set-ExecutionPolicy Bypass -Scope Process -Force; ' +
        '[System.Net.ServicePointManager]::SecurityProtocol = ' +
        '[System.Net.ServicePointManager]::SecurityProtocol -bor 3072; ' +
        'iex ((New-Object System.Net.WebClient).DownloadString(' +
        '''https://community.chocolatey.org/install.ps1''))'
      );
    end;

    // --------------------------------------------------------
    // Step 2: Install Git
    // --------------------------------------------------------
    WizardForm.StatusLabel.Caption := 'Installing Git...';
    if not CommandExists('git') then
      RunAndWait('choco', 'install git -y --no-progress');

    // --------------------------------------------------------
    // Step 3: Install Python 3.12
    // --------------------------------------------------------
    WizardForm.StatusLabel.Caption := 'Installing Python 3.12...';
    if not CommandExists('python') then
      RunAndWait('choco', 'install python312 -y --no-progress');

    // --------------------------------------------------------
    // Step 4: Install uv
    // --------------------------------------------------------
    WizardForm.StatusLabel.Caption := 'Installing uv (Python package manager)...';
    if not CommandExists('uv') then
      RunPowerShell('irm https://astral.sh/uv/install.ps1 | iex');

    // --------------------------------------------------------
    // Step 5: Install Node.js
    // --------------------------------------------------------
    WizardForm.StatusLabel.Caption := 'Installing Node.js...';
    if not CommandExists('node') then
      RunAndWait('choco', 'install nodejs-lts -y --no-progress');

    // --------------------------------------------------------
    // Step 6: Install Ollama
    // --------------------------------------------------------
    if IsComponentSelected('ollama') then
    begin
      WizardForm.StatusLabel.Caption := 'Installing Ollama...';
      if not CommandExists('ollama') then
        RunAndWait('choco', 'install ollama -y --no-progress');

      // Pull base models
      if IsComponentSelected('ollama\base_models') then
      begin
        WizardForm.StatusLabel.Caption := 'Pulling Ollama model: llama3.2:3b (fast)...';
        RunAndWait('ollama', 'pull llama3.2:3b');

        WizardForm.StatusLabel.Caption := 'Pulling Ollama model: llama3.1:8b (default)...';
        RunAndWait('ollama', 'pull llama3.1:8b');

        WizardForm.StatusLabel.Caption := 'Pulling Ollama model: mistral:7b (extract)...';
        RunAndWait('ollama', 'pull mistral:7b');

        WizardForm.StatusLabel.Caption := 'Pulling Ollama model: nomic-embed-text (embeddings)...';
        RunAndWait('ollama', 'pull nomic-embed-text');
      end;

      // Pull code model
      if IsComponentSelected('ollama\code_models') then
      begin
        WizardForm.StatusLabel.Caption := 'Pulling Ollama model: deepseek-coder-v2:16b (code)...';
        RunAndWait('ollama', 'pull deepseek-coder-v2:16b');
      end;

      // Pull deep model
      if IsComponentSelected('ollama\deep_model') then
      begin
        WizardForm.StatusLabel.Caption := 'Pulling Ollama model: llama3.1:70b (deep — this will take a while)...';
        RunAndWait('ollama', 'pull llama3.1:70b');
      end;
    end;

    // --------------------------------------------------------
    // Step 7: Install Obsidian
    // --------------------------------------------------------
    if IsComponentSelected('obsidian') then
    begin
      WizardForm.StatusLabel.Caption := 'Installing Obsidian...';
      RunAndWait('choco', 'install obsidian -y --no-progress');
    end;

    // --------------------------------------------------------
    // Step 8: Install Claude Code CLI
    // --------------------------------------------------------
    if IsComponentSelected('claude') then
    begin
      WizardForm.StatusLabel.Caption := 'Installing Claude Code CLI...';
      if not CommandExists('claude') then
        RunAndWait('npm', 'install -g @anthropic-ai/claude-code');
    end;

    // --------------------------------------------------------
    // Step 9: Install Beads
    // --------------------------------------------------------
    if IsComponentSelected('beads') then
    begin
      WizardForm.StatusLabel.Caption := 'Installing Beads issue tracker...';
      if not CommandExists('bd') then
        RunAndWait('npm', 'install -g @beads/bd');
    end;

    // --------------------------------------------------------
    // Step 10: Install Graphviz (optional)
    // --------------------------------------------------------
    if IsComponentSelected('graphviz') then
    begin
      WizardForm.StatusLabel.Caption := 'Installing Graphviz...';
      RunAndWait('choco', 'install graphviz -y --no-progress');
    end;

    // --------------------------------------------------------
    // Step 11: Install Tesseract (optional)
    // --------------------------------------------------------
    if IsComponentSelected('tesseract') then
    begin
      WizardForm.StatusLabel.Caption := 'Installing Tesseract OCR...';
      RunAndWait('choco', 'install tesseract -y --no-progress');
    end;

    // --------------------------------------------------------
    // Step 12: Configure persona
    // --------------------------------------------------------
    WizardForm.StatusLabel.Caption := 'Configuring persona: ' + PersonaFolder + '...';

    // Create .claude directory
    ForceDirectories(ClaudeDir);

    // Combine shared + persona CLAUDE.md
    SharedConfig := ExpandConstant('{app}') + '\shared\CLAUDE.md';
    PersonaConfig := ExpandConstant('{app}') + '\personas\' + PersonaFolder + '\CLAUDE.md';

    if FileExists(SharedConfig) and FileExists(PersonaConfig) then
    begin
      // Read shared config
      if LoadStringFromFile(SharedConfig, CombinedConfig) then
      begin
        CombinedConfig := CombinedConfig + #13#10 + #13#10 +
          '# --- Persona-Specific Configuration ---' + #13#10 + #13#10;
        // Append persona config
        if LoadStringFromFile(PersonaConfig, PersonaConfig) then
        begin
          CombinedConfig := CombinedConfig + PersonaConfig;
          SaveStringToFile(ClaudeDir + '\CLAUDE.md', CombinedConfig, False);
        end;
      end;
    end;

    // --------------------------------------------------------
    // Step 13: Create Obsidian vault (if selected)
    // --------------------------------------------------------
    if IsTaskSelected('vault') then
    begin
      WizardForm.StatusLabel.Caption := 'Creating knowledge base vault...';
      ForceDirectories(VaultPath + '\products');
      ForceDirectories(VaultPath + '\integrations');
      ForceDirectories(VaultPath + '\hardware');
      ForceDirectories(VaultPath + '\decisions');
      ForceDirectories(VaultPath + '\evaluations');
      ForceDirectories(VaultPath + '\marketing');
      ForceDirectories(VaultPath + '\support');
      ForceDirectories(VaultPath + '\strategy');
      ForceDirectories(VaultPath + '\templates');

      // Copy templates to vault
      FileCopy(
        ExpandConstant('{app}') + '\knowledge-base\obsidian\templates\evaluation-template.md',
        VaultPath + '\templates\evaluation-template.md', False);
      FileCopy(
        ExpandConstant('{app}') + '\knowledge-base\obsidian\templates\decision-record.md',
        VaultPath + '\templates\decision-record.md', False);
      FileCopy(
        ExpandConstant('{app}') + '\knowledge-base\obsidian\templates\kb-article.md',
        VaultPath + '\templates\kb-article.md', False);

      // Initialize git in vault
      RunAndWait('git', 'init "' + VaultPath + '"');
    end;

    // --------------------------------------------------------
    // Step 14: Add sidecar shortcut to PowerShell profile
    // --------------------------------------------------------
    if IsTaskSelected('shortcuts') then
    begin
      WizardForm.StatusLabel.Caption := 'Adding PowerShell sidecar shortcut...';
      RunPowerShell(
        '$profileDir = Split-Path $PROFILE; ' +
        'if (!(Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force }; ' +
        'if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }; ' +
        '$line = ''function sidecar { uv run --directory "$env:USERPROFILE\.claude\sidecar" python @args }''; ' +
        'if (!(Select-String -Path $PROFILE -Pattern "function sidecar" -Quiet -ErrorAction SilentlyContinue)) { ' +
        'Add-Content -Path $PROFILE -Value "`n# Reflex BV GenAI Sidecar shortcut`n$line" }'
      );
    end;

    // --------------------------------------------------------
    // Step 15: Initialize sidecar Python environment
    // --------------------------------------------------------
    WizardForm.StatusLabel.Caption := 'Setting up Python sidecar environment...';
    ForceDirectories(ClaudeDir + '\sidecar');
    RunPowerShell(
      'cd "' + ClaudeDir + '\sidecar"; ' +
      'if (!(Test-Path pyproject.toml)) { uv init }; ' +
      'uv add httpx beautifulsoup4 lxml ollama duckdb pandas'
    );

    WizardForm.StatusLabel.Caption := 'Installation complete!';
  end;
end;

// ============================================================
// Post-install message with next steps
// ============================================================
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption :=
      'The Reflex BV GenAI environment has been installed for the ' +
      GetPersonaFolder() + ' persona.' + #13#10 + #13#10 +
      'Next steps:' + #13#10 +
      '1. Open a new terminal (PowerShell) to refresh PATH' + #13#10 +
      '2. Run "claude" to start Claude Code' + #13#10 +
      '3. Inside Claude Code, run:' + #13#10 +
      '     /plugin install beads@beads-marketplace' + #13#10 +
      '4. Open Obsidian and add vault: ~/reflex-kb' + #13#10 + #13#10 +
      'Documentation is at: ' + ExpandConstant('{app}') + '\setup\';
  end;
end;

// ============================================================
// Pre-select components based on persona
// ============================================================
procedure RegisterExtraCloseQuery;
begin
  // This runs when the user clicks Install
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
end;

// Auto-select components based on persona after task selection
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // Uninstall cleanup if needed
end;
