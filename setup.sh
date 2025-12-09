#!/usr/bin/env bash
set -euo pipefail

TARGET_REPO="${1:-.}"         # first arg = target repo path, default current dir
SOURCE_DIR="${2:-}"           # optional local source dir for hooks (if omitted script will download from GitHub)
GITHUB_RAW_BASE="${3:-https://raw.githubusercontent.com/mahendraachwale8007-dev/precommit-hooks/main/hooks}"

GITHOOKS_DIR="$TARGET_REPO/.githooks"
mkdir -p "$GITHOOKS_DIR"

download_or_copy() {
  local name="$1"
  local dest="$GITHOOKS_DIR/$name"
  if [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/$name" ]; then
    cp "$SOURCE_DIR/$name" "$dest"
    echo "[INFO] Copied $name from $SOURCE_DIR to $dest"
  else
    local url="$GITHUB_RAW_BASE/$name"
    echo "[INFO] Downloading $url -> $dest"
    curl -fsSL "$url" -o "$dest"
  fi
  chmod +x "$dest" || true
}

# Acquire files
download_or_copy "secret_scan.py"
download_or_copy "patterns.yml"

# ensure python available
if command -v python3 >/dev/null 2>&1; then
  PY_CMD="python3"
elif command -v python >/dev/null 2>&1; then
  PY_CMD="python"
else
  echo "[ERROR] Python not found. Install Python 3 and re-run." >&2
  exit 2
fi

# ensure pip and pre-commit
$PY_CMD -m pip install --user --upgrade pip >/dev/null
$PY_CMD -m pip install --user pre-commit detect-secrets >/dev/null
echo "[OK] Installed/verified pre-commit and detect-secrets"

# write .pre-commit-config.yaml (backup if exists)
PCFG="$TARGET_REPO/.pre-commit-config.yaml"
if [ -f "$PCFG" ]; then
  cp "$PCFG" "$PCFG.bak_$(date +%Y%m%d%H%M%S)"
  echo "[INFO] Backed up existing $PCFG"
fi

cat > "$PCFG" <<'EOF'
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
EOF

echo "[OK] Wrote $PCFG"

# install pre-commit in target repo
pushd "$TARGET_REPO" >/dev/null
$PY_CMD -m pre_commit install
echo "[OK] pre-commit installed in $TARGET_REPO"

# run initial full check (expected to fail if secrets present)
$PY_CMD -m pre_commit run --all-files || echo "[INFO] pre-commit run returned non-zero exit (expected if secrets are found)."

popd >/dev/null

cat <<EOF

Setup complete. To test:
  cd $TARGET_REPO
  git add TestSecret.java
  git commit -m "test secret detection"

EOF
