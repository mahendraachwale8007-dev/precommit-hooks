# precommit-hooks (Centralized Secret Detection)

This repository contains a centralized pre-commit hook for detecting hardcoded secrets.

## Usage
In your project `.pre-commit-config.yaml`, add:
```yaml
repos:
  - repo: https://github.com/<your-username>/precommit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-secret-regex
```

Then install and test:
```bash
pip install pre-commit detect-secrets
pre-commit install
pre-commit run --all-files
```

## Purpose
Detects secrets like passwords, tokens, API keys before commit.
