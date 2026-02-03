<#
.SYNOPSIS
  Bootstrap installer to apply pre-commit setup across multiple repositories.

.DESCRIPTION
  - Verifies REAL Python 3 installation (not Microsoft Store alias)
  - Ensures PyYAML is available
  - Parses repos.yml using Python
  - Runs setup.ps1 for each configured repository
  - Fails fast on any prerequisite issue
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[OK]    $m" -ForegroundColor Green }
function Err($m)  { Write-Host "[ERROR] $m" -ForegroundColor Red }

$ROOT        = Split-Path -Parent $MyInvocation.MyCommand.Path
$reposFile   = Join-Path $ROOT "repos.yml"
$setupScript = Join-Path $ROOT "setup.ps1"

# ------------------------------------------------------------
# 1️⃣ HARDENED Python detection (FAIL FAST)
# ------------------------------------------------------------

$pythonCmd = $null
$pythonVersionOutput = ""

if (Get-Command py -ErrorAction SilentlyContinue) {
    try {
        $pythonVersionOutput = & py -3 --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $pythonVersionOutput -match '^Python\s+\d+') {
            $pythonCmd = "py -3"
        }
    } catch {}
}

if (-not $pythonCmd -and (Get-Command python -ErrorAction SilentlyContinue)) {
    try {
        $pythonVersionOutput = & python --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $pythonVersionOutput -match '^Python\s+\d+') {
            $pythonCmd = "python"
        }
    } catch {}
}

if (-not $pythonCmd) {
    Err "Python 3.x is required but not installed correctly."
    Write-Host ""
    Write-Host "What we checked:" -ForegroundColor Yellow
    Write-Host " - python / py command exists ❌ (Microsoft Store alias detected)"
    Write-Host " - Real Python runtime ❌"
    Write-Host ""
    Write-Host "Fix:" -ForegroundColor Yellow
    Write-Host "1. Install Python from https://www.python.org/downloads/"
    Write-Host "2. During install, CHECK 'Add Python to PATH'"
    Write-Host "3. Disable Store alias:"
    Write-Host "   Settings → Apps → Advanced app settings → App execution aliases"
    Write-Host "   Turn OFF python.exe and python3.exe"
    exit 2
}

Ok "Python verified: $pythonCmd ($pythonVersionOutput)"

# ------------------------------------------------------------
# 2️⃣ Validate required files
# ------------------------------------------------------------

if (-not (Test-Path $reposFile)) {
    Err "repos.yml not found: $reposFile"
    exit 3
}

if (-not (Test-Path $setupScript)) {
    Err "setup.ps1 not found in central repo"
    exit 4
}

# ------------------------------------------------------------
# 3️⃣ Ensure PyYAML is available
# ------------------------------------------------------------

& $pythonCmd -c "import yaml" 2>$null
if ($LASTEXITCODE -ne 0) {
    Info "PyYAML not found. Installing..."
    & $pythonCmd -m pip install --user pyyaml
    Ok "PyYAML installed"
} else {
    Ok "PyYAML available"
}

# ------------------------------------------------------------
# 4️⃣ Parse repos.yml using Python (SAFE)
# ------------------------------------------------------------

$repoList = & $pythonCmd -c "
import yaml
with open(r'$reposFile','r') as f:
    data = yaml.safe_load(f) or {}
for r in data.get('repos', []):
    p = r.get('path')
    if p:
        print(p)
"

# 🔒 NORMALIZE OUTPUT (critical fix)
if ($repoList -is [string]) {
    $repoList = @($repoList)
}

if (-not $repoList -or $repoList.Count -eq 0) {
    Err "No repositories found in repos.yml"
    exit 5
}

Ok "Found $($repoList.Count) repositories"

# ------------------------------------------------------------
# 5️⃣ Apply setup.ps1 to each repo
# ------------------------------------------------------------

foreach ($repo in $repoList) {

    if (-not (Test-Path $repo)) {
        Err "Repository path does not exist: $repo"
        exit 6
    }

    Ok "Applying setup to: $repo"

    try {
        powershell -ExecutionPolicy Bypass `
            -File $setupScript `
            -TargetRepo $repo
    } catch {
        Err "Setup failed for $repo"
        exit 7
    }
}

# ------------------------------------------------------------
# 6️⃣ Done
# ------------------------------------------------------------

Ok "Bootstrap completed successfully for all repositories"
exit 0
