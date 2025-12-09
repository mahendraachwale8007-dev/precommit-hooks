#!/usr/bin/env python3
"""
Pre-commit hook: scan staged files for secrets using regex + YAML-configured patterns.
Loads .githooks/patterns.yml (list of regex strings). If YAML fails or file missing,
falls back to built-in patterns.
"""

import re
import sys
import subprocess
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None  # we'll handle missing yaml gracefully

# -------------------------
# Built-in default patterns
# -------------------------
DEFAULT_PATTERNS = [
    r'(?i)(password|passwd|pwd)\s*[:=]\s*["\']?\S{4,}["\']?',
    r'(?i)(api[_-]?key|apikey|token|secret|access[_-]?key)\s*[:=]\s*["\']?\S{8,}["\']?',
    r'AKIA[0-9A-Z]{16}',
    r'AIza[0-9A-Za-z\-_]{35}',
    r'xox[baprs]-[A-Za-z0-9-]{10,}',
    r'-----BEGIN (RSA|PRIVATE|OPENSSH|DSA|EC) PRIVATE KEY-----',
    r'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+',
    # smart uuid detection - lower priority fallback (kept in defaults too)
    r'(?i)(?:vault|secret|token|key|credential|clientid|client_id|secret_id)[A-Za-z0-9_\-]*\s*[:=]\s*["\']?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}["\']?',
]

PATTERNS_FILE = Path('.githooks') / 'patterns.yml'
EXT_RE = re.compile(r'\.(py|java|js|ts|json|yaml|yml|env|properties|sh)$', re.I)

def load_patterns():
    if not PATTERNS_FILE.exists():
        return DEFAULT_PATTERNS
    if yaml is None:
        print(f"[WARN] PyYAML not installed; ignoring patterns.yml and using defaults.")
        return DEFAULT_PATTERNS
    try:
        with PATTERNS_FILE.open('r', encoding='utf-8') as f:
            cfg = yaml.safe_load(f)
        if isinstance(cfg, list) and all(isinstance(x, str) for x in cfg):
            return cfg
        else:
            print(f"[WARN] patterns.yml format invalid (expect top-level list). Using defaults.")
            return DEFAULT_PATTERNS
    except Exception as e:
        print(f"[WARN] Failed to parse patterns file {PATTERNS_FILE}: {e}")
        return DEFAULT_PATTERNS

def get_staged_files():
    res = subprocess.run(
        ['git', 'diff', '--cached', '--name-only', '--diff-filter=ACM'],
        capture_output=True, text=True
    )
    if res.returncode != 0:
        return []
    return [p.strip() for p in res.stdout.splitlines() if p.strip()]

def scan_file(path, compiled_patterns):
    try:
        text = Path(path).read_text(errors='ignore')
    except Exception:
        return []
    findings = []
    for pat in compiled_patterns:
        for m in re.finditer(pat, text, flags=re.MULTILINE):
            line_no = text.count('\n', 0, m.start()) + 1
            lines = text.splitlines()
            snippet = lines[line_no - 1].strip() if 0 <= line_no - 1 < len(lines) else ''
            findings.append((line_no, snippet, pat))
    return findings

def main():
    patterns = load_patterns()
    compiled = [re.compile(p) for p in patterns]

    staged = get_staged_files()
    secrets_found = {}

    for f in staged:
        if not EXT_RE.search(f):
            continue
        matches = scan_file(f, compiled)
        if matches:
            secrets_found[f] = matches

    if secrets_found:
        print("\n[ALERT] Potential secrets detected:")
        for f, findings in secrets_found.items():
            print(f"\nFile: {f}")
            for line, snippet, pat in findings:
                print(f"  Line {line}: {snippet[:200]}")
        print("\n[BLOCKED] Commit blocked! Remove or mask secrets before committing.")
        sys.exit(1)

    print("[OK] No secrets detected. Commit allowed.")
    sys.exit(0)

if __name__ == "__main__":
    main()
