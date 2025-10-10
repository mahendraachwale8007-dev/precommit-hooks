#!/usr/bin/env python3
"""Centralized secret scan hook."""
import re, sys, math
from pathlib import Path

PATTERNS = [
    re.compile(r'(?i)(password|passwd|pwd)\s*[:=]\s*["\']?[^"\']{4,}["\']?'),
    re.compile(r'(?i)(api[_-]?key|apikey|token|secret|access[_-]?key)\s*[:=]\s*["\']?[^"\']{8,}["\']?'),
    re.compile(r'AKIA[0-9A-Z]{16}'),
    re.compile(r'AIza[0-9A-Za-z\-_]{35}'),
    re.compile(r'xox[baprs]-[A-Za-z0-9-]{10,}'),
    re.compile(r'-----BEGIN (RSA|PRIVATE|OPENSSH|DSA|EC) PRIVATE KEY-----'),
    re.compile(r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+')
]
ENTROPY_MIN_LEN, ENTROPY_THRESHOLD = 20, 4.5

def shannon_entropy(s):
    from math import log2
    freq = {ch: s.count(ch) for ch in set(s)}
    return -sum((count/len(s))*log2(count/len(s)) for count in freq.values()) if s else 0

def scan_file(path):
    text = Path(path).read_text(encoding='utf-8', errors='ignore')
    findings = []
    for regex in PATTERNS:
        for m in regex.finditer(text):
            line_no = text.count('\n', 0, m.start()) + 1
            snippet = text.splitlines()[line_no-1].strip()
            findings.append((line_no, snippet))
    return findings

def main(files):
    issues = {}
    for f in files:
        if Path(f).is_file():
            res = scan_file(f)
            if res:
                issues[f] = res
    if issues:
        print("\n[SECURITY] Potential secrets detected:")
        for f, res in issues.items():
            print(f"File: {f}")
            for line, snippet in res:
                print(f"  Line {line}: {snippet}")
        print("\n[BLOCKED] Commit aborted.")
        sys.exit(1)
    print("[OK] No secrets detected.")
    sys.exit(0)

if __name__ == '__main__':
    main(sys.argv[1:])
