#!/usr/bin/env python3
import re, subprocess, sys, pathlib


PATTERNS = [
    r'(?i)(password|passwd|pwd)\s*[:=]\s*["\']?\S{4,}["\']?',
    r'(?i)(api[_-]?key|apikey|token|secret)\s*[:=]\s*["\']?\S{8,}["\']?',
    r'AKIA[0-9A-Z]{16}',                                            # AWS Access Key
    r'AIza[0-9A-Za-z\-_]{35}',                                      # Google API Key
    r'xox[baprs]-[A-Za-z0-9-]{10,}',                                # Slack Token
    r'-----BEGIN (RSA|PRIVATE|OPENSSH|DSA|EC) PRIVATE KEY-----',    # Private Key
    r'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+',      # JWT Token

    # Smart UUID detection: only flag UUIDs when variable name looks secret-ish.
    # This will catch: VAULT_SECRET_ID=fed18384-862a-c948-f6d1-7fb2e4e3447e
    r'(?i)(?:vault|secret|token|key|credential|clientid|client_id|secret_id)[A-Za-z0-9_\-]*\s*[:=]\s*["\']?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}["\']?',

    # Lower-priority: generic UUID (can be noisy, will comment out if too many false positives)
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
]

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
        text = pathlib.Path(path).read_text(errors='ignore')
    except Exception:
        return []
    findings = []
    for pattern in PATTERNS:
        # use re.MULTILINE to match per-line constructs
        for match in re.finditer(pattern, text, flags=re.MULTILINE):
            line_no = text.count('\n', 0, match.start()) + 1
            lines = text.splitlines()
            snippet = lines[line_no - 1].strip() if 0 <= line_no - 1 < len(lines) else ''
            findings.append((line_no, snippet))
    return findings

def main():
    staged_files = get_staged_files()
    secrets_found = {}

    for f in staged_files:
        # Only scan relevant files
        if not EXT_RE.search(f):
            continue
        matches = scan_file(f)
        if matches:
            secrets_found[f] = matches

    if secrets_found:
        print("\n[ALERT] Potential secrets detected:")
        for f, findings in secrets_found.items():
            print(f"\nFile: {f}")
            for line, snippet in findings:
                print(f"  Line {line}: {snippet[:200]}")
        print("\n[BLOCKED] Commit blocked! Remove or mask secrets before committing.")
        sys.exit(1)

    print("[OK] No secrets detected. Commit allowed.")
    sys.exit(0)

if __name__ == "__main__":
    main()
