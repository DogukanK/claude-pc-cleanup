#!/bin/bash
# Regression test for safe_delete.sh's guardrails. Run this after editing
# safe_delete.sh (or scan.sh) to confirm the safety properties still hold —
# this skill runs repeatedly over a long time, so a silent regression in the
# guardrails would be easy to miss otherwise.
#
# Usage: selftest.sh
# Exits 0 if every check behaves as expected, 1 otherwise. Never touches
# anything outside its own temp directory and never touches the real
# ~/.local/share/claude/versions or ~/.Trash.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE_DELETE="$HERE/safe_delete.sh"
FAILURES=0

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

check() {
  local desc="$1" expect="$2" got="$3"
  if [ "$got" = "$expect" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected '$expect', got '$got')"
    FAILURES=$((FAILURES + 1))
  fi
}

bash -n "$SAFE_DELETE" 2>/dev/null
check "safe_delete.sh has valid syntax" "0" "$?"
bash -n "$HERE/scan.sh" 2>/dev/null
check "scan.sh has valid syntax" "0" "$?"

# --- Should DELETE: known-safe categories ---
mkdir -p "$TMP/proj/node_modules/pkg"
bash "$SAFE_DELETE" "$TMP/proj/node_modules" >/dev/null 2>&1
check "deletes node_modules" "no" "$([ -e "$TMP/proj/node_modules" ] && echo yes || echo no)"

mkdir -p "$TMP/proj2/.venv/bin"
bash "$SAFE_DELETE" "$TMP/proj2/.venv" >/dev/null 2>&1
check "deletes .venv" "no" "$([ -e "$TMP/proj2/.venv" ] && echo yes || echo no)"

mkdir -p "$TMP/proj3/__pycache__"
bash "$SAFE_DELETE" "$TMP/proj3/__pycache__" >/dev/null 2>&1
check "deletes __pycache__" "no" "$([ -e "$TMP/proj3/__pycache__" ] && echo yes || echo no)"

mkdir -p "$TMP/proj4/.terraform/providers/x"
touch "$TMP/proj4/.terraform.lock.hcl"
bash "$SAFE_DELETE" "$TMP/proj4/.terraform/providers" >/dev/null 2>&1
check "deletes .terraform/providers" "no" "$([ -e "$TMP/proj4/.terraform/providers" ] && echo yes || echo no)"

# --- Should REFUSE: protected categories ---
mkdir -p "$TMP/proj5/.git/objects"
bash "$SAFE_DELETE" "$TMP/proj5/.git" >/dev/null 2>&1
check "refuses .git" "yes" "$([ -e "$TMP/proj5/.git" ] && echo yes || echo no)"

touch "$TMP/proj6-terraform.tfstate"
mv "$TMP/proj6-terraform.tfstate" "$TMP/terraform.tfstate" 2>/dev/null
bash "$SAFE_DELETE" "$TMP/terraform.tfstate" >/dev/null 2>&1
check "refuses terraform.tfstate" "yes" "$([ -e "$TMP/terraform.tfstate" ] && echo yes || echo no)"

mkdir -p "$TMP/random_unclassified_dir"
bash "$SAFE_DELETE" "$TMP/random_unclassified_dir" >/dev/null 2>&1
check "refuses an unrecognized path" "yes" "$([ -e "$TMP/random_unclassified_dir" ] && echo yes || echo no)"

bash "$SAFE_DELETE" "$HOME" >/dev/null 2>&1
check "refuses the home directory itself" "yes" "$([ -e "$HOME" ] && echo yes || echo no)"

# --- Active Claude Code version must never be deletable ---
CLAUDE_BIN="$(command -v claude 2>/dev/null)"
if [ -n "$CLAUDE_BIN" ] && [ -L "$CLAUDE_BIN" ]; then
  # Each entry under versions/ can be either a directory or a single
  # executable file depending on the CLI's install format -- don't assume
  # either, just check it exists.
  ACTIVE_DIR="$(readlink -f "$CLAUDE_BIN" 2>/dev/null || readlink "$CLAUDE_BIN" 2>/dev/null)"
  if [ -n "$ACTIVE_DIR" ] && [ -e "$ACTIVE_DIR" ]; then
    OUT="$(bash "$SAFE_DELETE" "$ACTIVE_DIR" 2>&1)"
    case "$OUT" in
      REFUSED*) echo "PASS: refuses the active Claude Code version ($ACTIVE_DIR)" ;;
      *) echo "FAIL: did NOT refuse the active Claude Code version ($ACTIVE_DIR) -- output: $OUT"; FAILURES=$((FAILURES + 1)) ;;
    esac
    check "active Claude Code version still exists after the attempt" "yes" "$([ -e "$ACTIVE_DIR" ] && echo yes || echo no)"
  fi
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "$FAILURES check(s) FAILED -- do not trust safe_delete.sh until this is fixed."
  exit 1
fi
