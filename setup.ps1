<#
.SYNOPSIS
  Installer to copy canonical pre-commit hook files into a target repo and install hooks (Windows PowerShell).

.DESCRIPTION
  Copies hooks/secret_scan.py and hooks/patterns.yml into TARGET\.githooks,
  creates .pre-commit-config.yaml pointing to local hook, installs pre-commit and detect-secrets,
  runs pre-commit install and pre-commit run --all-files.

.PARAMETER TargetRepo
  Path to the consumer repo. Default is current directory.

.PARAMETER SourceDir
  Path where the canonical hooks live. If omitted, script will attempt to download from GitHub raw URL.

.PARAMETER GithubRawBase
  Base URL to download raw hook files if SourceDir is absent. Default points to your central repo's main branch.

.EXAMPLE
  .\setup.ps1 -TargetRepo "C:\projects\demo-consumer" -SourceDir "..\precommit-hooks"

  Or (download from GitHub):
  .\setup.ps1 -TargetRepo "." -GithubRawBase "https://raw.githubusercontent.com/mahendraachwale8007-dev/precommit-hooks/main/hooks"
#>

param(
    [string]$TargetRepo = ".",
    [string]$SourceDir = "",
    [string]$GithubRawBase = "https://raw.githubusercontent.com/mahendraachwale8007-dev/precommit-hooks/main/hooks"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Ok($msg){ Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Err($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Resolve full paths
try {
    $target = (Resolve-Path -Path $TargetRepo).Path
} catch {
    Write-Err "Target repository path '$TargetRepo' not found."
    exit 1
}

$githooks = Join-Path $target ".githooks"
New-Item -Path $githooks -ItemType Directory -Force | Out-Null

# Helper: copy from local source or download
function Get-File($name) {
    $localPath = ""
    if ($SourceDir) {
        try {
            $resolvedSource = (Resolve-Path -Path $SourceDir).Path
            $localPath = Join-Path $resolvedSource $name
        } catch {
            $localPath = ""
        }
    }

    $destPath = Join-Path $githooks $name

    if ($localPath -and (Test-Path $localPath)) {
        Copy-Item -Path $localPath -Destination $destPath -Force
        Write-Info "Copied $name from local source to $destPath"
    } else {
        $url = "$GithubRawBase/$name"
        Write-Info "Downloading $url -> $destPath"
        try {
            # Use Invoke-WebRequest; -UseBasicParsing for older PS versions
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing -ErrorAction Stop
            Write-Info "Downloaded $name to $destPath"
        } catch {
            # safer interpolation of exception message
            Write-Err "Failed to download $($url): $($_.Exception.Message)"
            throw
        }
    }
    return $destPath
}

# Acquire hook files
try {
    $secretScanPath = Get-File "secret_scan.py"
    $patternsPath = Get-File "patterns.yml"
} catch {
    Write-Err "Failed to obtain canonical hook files. Aborting."
    exit 1
}

# Ensure python is available (prefer py -3 then python)
$pythonCmd = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCmd = "py -3"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCmd = "python"
} else {
    Write-Err "Python not found on PATH. Please install Python 3.x and re-run."
    Write-Host "If Python is installed but not on PATH, either add it to PATH or pass full path in the script (edit entry in .pre-commit-config.yaml)."
    exit 2
}

Write-Info "Using Python command: $pythonCmd"

# Ensure pip & pre-commit & detect-secrets installed (use python -m pip)
try {
    & $pythonCmd -m pip install --user --upgrade pip | Out-Null
    & $pythonCmd -m pip install --user pre-commit detect-secrets | Out-Null
    Write-Ok "Installed/verified pre-commit and detect-secrets"
} catch {
    Write-Err "Failed to install required Python packages: $($_.Exception.Message)"
    exit 4
}

# Create .pre-commit-config.yaml in target (do not overwrite if exists — backup)
$pcfg = Join-Path $target ".pre-commit-config.yaml"
if (Test-Path $pcfg) {
    $bak = "$pcfg.bak_$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item -Path $pcfg -Destination $bak
    Write-Info "Existing .pre-commit-config.yaml backed up to $bak"
}

# Use single-quoted here-string to avoid accidental variable expansion and nested quote issues.
$precommit_content = @'
repos:
  - repo: local
    hooks:
      - id: custom-secret-regex
        name: Custom Secret Regex
        entry: python .githooks/secret_scan.py
        language: system
        files: '\.(py|java|js|ts|json|yaml|yml|env|properties|sh)$'
        pass_filenames: false

      - id: detect-secrets-local
        name: Detect Secrets (Local)
        entry: bash -c "git diff --cached --name-only | xargs detect-secrets scan"
        language: system
        pass_filenames: false
'@

try {
    # Write file with UTF8 encoding and a trailing newline
    $precommit_content | Out-File -FilePath $pcfg -Encoding utf8 -Force
    Write-Ok "Wrote .pre-commit-config.yaml to $pcfg"
} catch {
    Write-Err "Failed to write .pre-commit-config.yaml: $($_.Exception.Message)"
    exit 5
}

# Install pre-commit hooks in the target repo
Push-Location $target
try {
    # Use the python module interface; this will create .git/hooks/pre-commit
    & $pythonCmd -m pre_commit.__main__ install
    Write-Ok "pre-commit installed in repo"
} catch {
    Write-Err "pre-commit install failed: $($_.Exception.Message)"
    Pop-Location
    exit 3
}

# Run initial check (non-fatal if hooks return non-zero)
try {
    & $pythonCmd -m pre_commit.__main__ run --all-files
    Write-Ok "pre-commit run --all-files completed"
} catch {
    Write-Info "pre-commit run returned non-zero (this is expected if hooks find secrets or if an environment issue exists). See output above for details."
}

Pop-Location

Write-Host "`nSetup complete. To test manually:"
Write-Host "  cd $target"
Write-Host "  git add <file-with-secret-or-clean-file>"
Write-Host "  git commit -m 'test commit'"
Write-Host ""
Write-Host "Note: If you prefer to run the installer by downloading it directly from GitHub, run:"
Write-Host "  powershell -ExecutionPolicy Bypass -Command `"iwr -UseBasicParsing https://raw.githubusercontent.com/mahendraachwale8007-dev/precommit-hooks/main/setup.ps1 -OutFile setup.ps1; ./setup.ps1 -TargetRepo '.'`" 
