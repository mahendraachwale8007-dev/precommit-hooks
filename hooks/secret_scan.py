import re
import subprocess
import sys
import pathlib
import yaml


# ============================================================
# Load patterns dynamically from YAML file
# ============================================================
def load_patterns():
    yaml_path = pathlib.Path(__file__).parent / "patterns.yml"
    with open(yaml_path, "r", encoding="utf-8") as f:
        config = yaml.safe_load(f)

    return [re.compile(p) for p in config.get("regex_patterns", [])]


PATTERNS = load_patterns()

EXT_RE = re.compile(r'\.(py|java|js|ts|json|ya?ml|env|properties|sh)$', re.I)


def get_staged_files():
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True, text=True
    )
    return [f.strip() for f in result.stdout.splitlines() if f.strip()]


def scan_file(path):
    try:
        text = pathlib.Path(path).read_text(errors="ignore")
    except Exception:
        return []

    findings = []
    lines = text.splitlines()

    for regex in PATTERNS:
        for match in regex.finditer(text):
            line_no = text.count("\n", 0, match.start()) + 1
            snippet = lines[line_no - 1].strip() if 0 <= line_no - 1 < len(lines) else ""
            findings.append((line_no, snippet))

    return findings


def main():
    staged_files = get_staged_files()
    secrets_found = {}

    for f in staged_files:
        if EXT_RE.search(f):
            matches = scan_file(f)
            if matches:
                secrets_found[f] = matches

    if secrets_found:
        print("\n[ALERT] Potential secrets detected:")
        for f, matches in secrets_found.items():
            print(f"\nFile: {f}")
            for line, snippet in matches:
                print(f"  Line {line}: {snippet[:200]}")
        print("\n[BLOCKED] Commit blocked! Remove or mask secrets before committing.")
        sys.exit(1)

    print("[OK] No secrets detected. Commit allowed.")
    sys.exit(0)


if __name__ == "__main__":
    main()
