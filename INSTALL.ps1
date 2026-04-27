# =============================================================================
# Claude + Elementor Kit — Installer (Windows)
#
# Copies the skill and setup script into your ~/.claude/ folder so Claude Code
# can find them automatically. Safe to re-run.
#
# Usage: right-click → "Run with PowerShell"
#   or:  open PowerShell, navigate to this folder, and run:
#          .\INSTALL.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }

Write-Host @"

  +-----------------------------------------------+
  |   Claude + Elementor Kit -- Installer          |
  |   ----------------------------------          |
  |   Installs the skill + setup script into      |
  |   ~/.claude/ so Claude Code can find them.    |
  +-----------------------------------------------+

"@

# Locate kit files
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$SrcFiles = Join-Path $Here "files"

if (-not (Test-Path $SrcFiles)) {
    Write-Fail "Cannot find $SrcFiles -- run this script from the kit folder."
    exit 1
}
if (-not (Test-Path (Join-Path $SrcFiles "SKILL.md"))) {
    Write-Fail "Missing SKILL.md in files/."
    exit 1
}
if (-not (Test-Path (Join-Path $SrcFiles "setup-elementor-mcp.sh"))) {
    Write-Fail "Missing setup-elementor-mcp.sh in files/."
    exit 1
}

Write-Step "Creating destination folders"
$ClaudeDir  = Join-Path $HOME ".claude"
$SkillDir   = Join-Path $ClaudeDir "skills\elementor-mcp"
$ScriptDir  = Join-Path $ClaudeDir "scripts"

New-Item -ItemType Directory -Force -Path $SkillDir  | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptDir | Out-Null

Write-Ok $SkillDir
Write-Ok $ScriptDir

Write-Step "Copying files"

# Skill
$SkillDest = Join-Path $SkillDir "SKILL.md"
if (Test-Path $SkillDest) {
    Write-Warn "SKILL.md already exists."
    $ans = Read-Host "    Overwrite? [y/N]"
    if ($ans -match '^[Yy]$') {
        Copy-Item (Join-Path $SrcFiles "SKILL.md") $SkillDest -Force
        Write-Ok "Overwrote SKILL.md"
    } else {
        Write-Warn "Skipped SKILL.md"
    }
} else {
    Copy-Item (Join-Path $SrcFiles "SKILL.md") $SkillDest
    Write-Ok "Installed SKILL.md"
}

# Script
$ScriptDest = Join-Path $ScriptDir "setup-elementor-mcp.sh"
if (Test-Path $ScriptDest) {
    Write-Warn "setup-elementor-mcp.sh already exists."
    $ans = Read-Host "    Overwrite? [y/N]"
    if ($ans -match '^[Yy]$') {
        Copy-Item (Join-Path $SrcFiles "setup-elementor-mcp.sh") $ScriptDest -Force
        Write-Ok "Overwrote setup-elementor-mcp.sh"
    } else {
        Write-Warn "Skipped setup-elementor-mcp.sh"
    }
} else {
    Copy-Item (Join-Path $SrcFiles "setup-elementor-mcp.sh") $ScriptDest
    Write-Ok "Installed setup-elementor-mcp.sh"
}

Write-Host @"

  [OK] Install complete

  Files installed at:
    ~/.claude/skills/elementor-mcp/SKILL.md
    ~/.claude/scripts/setup-elementor-mcp.sh

  IMPORTANT FOR WINDOWS USERS:

    The setup script is a bash script. To run it, you need
    Git Bash (which most Windows developers already have):

      Download: https://git-scm.com/download/win
      (Includes bash, curl, python, zip, and other tools.)

    Once Git Bash is installed:

      1. Open Git Bash in your project folder
         (Right-click in the folder -> "Git Bash Here")

      2. Run the setup wizard:
         bash ~/.claude/scripts/setup-elementor-mcp.sh

      3. Answer the 4 questions.

      4. Quit and reopen Claude Code in that folder.

      5. Tell Claude: "use the elementor MCP to build my homepage"

  Read the docs:
    docs/QUICKSTART.md   -- short guide
    docs/LESSONS.md      -- deep dive

"@ -ForegroundColor White

Read-Host "Press Enter to close"
