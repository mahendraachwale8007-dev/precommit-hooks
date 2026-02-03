<#
.SYNOPSIS
  Bootstrap installer to apply centralized pre-commit hooks
  across multiple local repositories.

.DESCRIPTION
  Reads repos.yml and runs setup.ps1 for each listed repository.
  This allows developers to secure all their repos with one command.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Ok($msg){ Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Resolve script root
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReposFile = Join-Path $RootDir "repos.yml"
$SetupScript = Join-Path $RootDir "setup.ps1"

# Validate files
if (-not (Test-Path $ReposFile)) {
    Write-Err "repos.yml not found in $RootDir"
    exit 1
}

if (-not (Test-Path $SetupScript)) {
    Write-Err "setup.ps1 not found in $RootDir"
    exit 1
}

# Check Python ONCE
if (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCmd = "py -3"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCmd = "python"
} else {
    Write-Err "Python 3.x not found. Please install Python and re-run."
    exit 2
}

Write-Ok "Python detected"

# Install PyYAML if missing (for parsing repos.yml)
try {
    & $pythonCmd - << 'EOF'
import yaml
EOF
} catch {
    Write-Info "Installing PyYAML"
    & $pythonCmd -m pip install --user pyyaml | Out-Null
}

# Load repos.yml
$repos = & $pythonCmd - << 'EOF'
import yaml, sys
with open("repos.yml") as f:
    data = yaml.safe_load(f)
for r in data.get("repos", []):
    print(f"{r['name']}|{r['path']}")
EOF

Write-Host ""

foreach ($line in $repos) {
    $parts = $line.Split("|")
    $name = $parts[0]
    $path = $parts[1]

    Write-Info "Processing repo: $name"

    if (-not (Test-Path $path)) {
        Write-Warn "Path not found, skipping: $path"
        continue
    }

    if (-not (Test-Path (Join-Path $path ".git"))) {
        Write-Warn "Not a git repo, skipping: $path"
        continue
    }

    try {
        & $SetupScript -TargetRepo $path
        Write-Ok "Hooks installed for $name"
    } catch {
        Write-Warn "Failed for $name — continuing"
    }

    Write-Host ""
}

Write-Ok "Bootstrap completed for all repositories"
