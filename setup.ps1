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
$ErrorActionPreference = "Stop"

function Write-Ok($msg){ Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Err($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Resolve full paths
try {
    $target = (Resolve-Path -Path $TargetRepo).Path
} catch {
    Write-Err "Target path '$TargetRepo' does not exist."
    exit 1
}

$githooks = Join-Path $target ".githooks"
if (-not (Test-Path $githooks)) {
    New-Item -Path $githooks -ItemType Directory -Force | Out-Null
    Write-Info "Created directory: $githooks"
} else {
    Write-Info "Using existing directory: $githooks"
}

# Helper: copy from local source or download
function Get-File($name) {
    param($name)

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
            # Use Invoke-WebRequest; for PS Core this works without -UseBasicParsing
            Invoke-WebRequest -Uri $url -OutFile $destPath -ErrorAction Stop
            Write-Info "Downloaded $name to $destPath"
        } catch {
            Write-Err "Failed to download $url. Error: $($_.Exception.Message)"
            throw
        }
    }
    return $destPath
}

# Acquire hook files (secret_scan.py and patterns.yml)
try {
    $secretScanPath = Get-File "secret_scan.py"
    $patternsPath = Get-File "patterns.yml"
} catch {
    Write-Err "Failed to obtain canonical hook files. Aborting."
    exit 1
}

# Ensure python is available (try 'py' then 'python')
$pythonCmd = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCmd = "py -3"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCmd = "python"
} else {
    Write-Err "Python not found on PATH. Please install Python 3.x and re-run the installer."
    exit 2
}

Write-Info "Using Python command: $pythonCmd"

# Ensure pip & pre-commit & detect-secrets installed (use python -m pip)
try {
    & $pythonCmd -m pip install --user --upgrade pip | Out-Null
    & $pythonCmd -m pip install --user pre-commit detect-secrets | Out-Null
    Write-Ok "Installed/verified pre-commit and detect-secrets"
} catch {
    Write-Err "Failed to install Python packages: $($_.Exception.Message)"
    exit 3
}

# Create .pre-commit-config.yaml in target (do not overwrite if exists — backup)
$pcfg = Join-Path $target ".pre-commit-config.yaml"
if (Test-Path $pcfg) {
    $bak = "$pcfg.bak_$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item -Path $pcfg -Destination $bak -Force
    Write-Info "Existing .pre-commit-config.yaml backed up to $bak"
}

# Use a single-quoted here-string to avoid nested quoting issues
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

# Write file
try {
    Set-Content -Path $pcfg -Value $precommit_content -NoNewline -Force -Encoding UTF8
    Write-Ok "Wrote .pre-commit-config.yaml to $pcfg"
} catch {
    Write-Err "Failed to write .pre-commit-config.yaml: $($_.Exception.Message)"
    exit 4
}

# Install pre-commit hooks in the target repo
Push-Location $target
try {
    & $pythonCmd -m pre_commit.__main__ install
    Write-Ok "pre-commit installed in repo"
} catch {
    Write-Err "pre-commit install failed: $($_.Exception.Message)"
    Pop-Location
    exit 5
}

# Run initial check (non-fatal: if it returns non-zero we continue)
try {
    & $pythonCmd -m pre_commit.__main__ run --all-files
    Write-Ok "pre-commit run --all-files completed"
} catch {
    Write-Info "pre-commit run returned non-zero (this is expected if the hook finds secrets or environment differs). See output above."
}

Pop-Location

# Final helpful message (single-quoted here-string - avoids quote issues)
$finalMessage = @'
Setup complete. To test manually:
  cd <your-repo-path>
  git add <file-with-secret-or-clean-file>
  git commit -m "test commit"

If you prefer to run the installer directly from GitHub:
  powershell -ExecutionPolicy Bypass -Command "iwr -UseBasicParsing https://raw.githubusercontent.com/mahendraachwale8007-dev/precommit-hooks/main/setup.ps1 -OutFile setup.ps1; ./setup.ps1 -TargetRepo '.'"

Notes:
 - The installer copies hooks into .githooks and writes a local .pre-commit-config.yaml that points to the local hook.
 - If you kept SourceDir empty, files were downloaded from your central repo's raw URLs.
 - If pre-commit reports missing Python from git's environment, try running this script from PowerShell (not cmd) and ensure python/py is available on PATH.
'@

Write-Host ""
Write-Host $finalMessage

# Exit with success
exit 0
