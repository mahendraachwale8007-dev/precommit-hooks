#!/usr/bin/env python3
"""
Centralized secret scan hook (reads regex list from patterns.yml).
"""
import re
import sys
import subprocess
from pathlib import Path

# default fallback patterns (used if patterns.yml can't be read)
DEFAULT_PATTERNS = [
    r'(?i)(password|passwd|pwd)\s*[:=]\s*["\']?\S{4,}["\']?',
    r'(?i)(api[_-]?key|apikey|token|secret|access[_-]?key)\s*[:=]\s*["\']?\S{8,}["\']?',
    r'AKIA[0-9A-Z]{16}',
    r'AIza[0-9A-Za-z\-_]{35}',
    r'xox[baprs]-[A-Za-z0-9-]{10,}',
    r'-----BEGIN (RSA|PRIVATE|OPENSSH|DSA|EC) PRIVATE KEY-----',
    r'eyJ[a-zA-Z0-9_-]{10,}\.[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+',
    r'(?i)(?:vault|secret|token|key|credential|clientid|client_id|secret_id)[A-Za-z0-9_\-]*\s*[:=]\s*["\']?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}["\']?',
]

def load_patterns():
    # Try to load patterns.yml from same folder as this script
    try:
        import yaml
    except Exception:
        # If PyYAML is not installed, print note and return defaults
        return DEFAULT_PATTERNS

    script_dir = Path(__file__).resolve().parent
    candidates = [
        script_dir / "patterns.yml",          # local copy (.githooks/patterns.yml)
        script_dir / ".." / "hooks" / "patterns.yml",  # if run from cloned central layout
        script_dir / "hooks" / "patterns.yml",
    ]
    for p in candidates:
        p = p.resolve()
        if p.exists():
            try:
                with p.open("r", encoding="utf-8") as f:
                    cfg = yaml.safe_load(f)
                # Accept either top-level list OR {patterns: [...]}
                if isinstance(cfg, list):
                    return cfg
                if isinstance(cfg, dict) and "patterns" in cfg and isinstance(cfg["patterns"], list):
                    return cfg["patterns"]
            except Exception as e:
                print(f"[WARN] Failed to parse patterns file {p}: {e}", file=sys.stderr)
                break
    return DEFAULT_PATTERNS

PATTERNS = [re.compile(p) for p in load_patterns()]

# file extensions to scan
EXT_RE = re.compile(r'\.(py|java|js|ts|json|yaml|yml|env|properties|sh)$', re.I)

def get_staged_files():
    result = subprocess.run(
        ['git', 'diff', '--cached', '--name-only', '--diff-filter=ACM'],
        capture_output=True, text=True
    )
    return [f.strip() for f in result.stdout.splitlines() if f.strip()]

def scan_file(path):
    try:
        text = Path(path).read_text(errors='ignore')
    except Exception:
        return []
    findings = []
    for regex in PATTERNS:
        for m in regex.finditer(text):
            line_no = text.count('\n', 0, m.start()) + 1
            snippet = text.splitlines()[line_no-1].strip() if line_no-1 < len(text.splitlines()) else ''
            findings.append((line_no, snippet))
    return findings

def main():
    files = get_staged_files()
    issues = {}
    for f in files:
        if not EXT_RE.search(f):
            continue
        res = scan_file(f)
        if res:
            issues[f] = res
    if issues:
        print("\n[ALERT] Potential secrets detected:")
        for f, res in issues.items():
            print(f"\nFile: {f}")
            for line, snippet in res:
                print(f"  Line {line}: {snippet}")
        print("\n[BLOCKED] Commit blocked! Remove or mask secrets before committing.")
        sys.exit(1)
    print("[OK] No secrets detected.")
    sys.exit(0)

if __name__ == "__main__":
    main()
