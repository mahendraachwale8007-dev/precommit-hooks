# top of secret_scan.py (pseudo)
import yaml, re, sys, pathlib

DEFAULT_PATTERNS = [
    r'(?i)(password|passwd|pwd)\s*[:=]\s*["\']?\S{4,}["\']?',
    r'(?i)(api[_-]?key|apikey|token|secret|access[_-]?key)\s*[:=]\s*["\']?\S{8,}["\']?',
    r'AKIA[0-9A-Z]{16}',
    r'AIza[0-9A-Za-z\-_]{35}',
    r'xox[baprs]-[A-Za-z0-9-]{10,}',
    r'-----BEGIN (RSA|PRIVATE|OPENSSH|DSA|EC) PRIVATE KEY-----',
    r'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+',
]

def load_patterns():
    p = pathlib.Path('.githooks/patterns.yml')
    if not p.exists():
        return DEFAULT_PATTERNS
    try:
        with p.open('r', encoding='utf-8') as f:
            cfg = yaml.safe_load(f)
            if isinstance(cfg, list) and all(isinstance(x, str) for x in cfg):
                return cfg
            else:
                print(f"[WARN] patterns.yml not a list or invalid — using defaults.")
                return DEFAULT_PATTERNS
    except Exception as e:
        print(f"[WARN] Failed to parse patterns file {p}: {e}")
        return DEFAULT_PATTERNS

PATTERNS = load_patterns()
# ... rest of your scanning code uses PATTERNS ...
