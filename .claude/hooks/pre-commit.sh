#!/usr/bin/env bash
# Block commits that would include sensitive files.

BLOCKED_PATTERNS='\.(env|key|pem|pfx|p12)$|id_rsa|id_ed25519|secrets\.json|creds\.md|aws_credentials|\.npmrc|terraform\.tfvars'

if git diff --cached --name-only | grep -qE "$BLOCKED_PATTERNS"; then
  echo "BLOCKED: attempt to commit sensitive files"
  exit 1
fi

# Optional: run gitleaks if installed
if command -v gitleaks &>/dev/null; then
  gitleaks detect --staged --no-git 2>/dev/null && {
    echo "BLOCKED: gitleaks found secrets"
    exit 1
  }
fi
