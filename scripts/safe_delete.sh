#!/bin/bash
# Guardrailed delete for pc-cleanup. Only removes paths matching a known-safe
# category. Refuses anything else, even if the caller (the model) got it wrong.
#
# This exists because the model calling this skill will run repeatedly, in
# different sessions, over a long time. Guardrails belong in code, not in
# instructions that could be misread or skipped one day.
#
# Usage: safe_delete.sh <absolute_path> [<absolute_path> ...]
# Logs every deletion (or refusal) with a size and timestamp to:
#   ~/.claude/pc-cleanup-history.log

set -uo pipefail

LOG=~/.claude/pc-cleanup-history.log
touch "$LOG" 2>/dev/null

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

is_active_claude_version_dir() {
  local path="$1"
  local claude_bin active
  claude_bin="$(command -v claude 2>/dev/null)"
  [ -z "$claude_bin" ] && return 1
  active="$(readlink -f "$claude_bin" 2>/dev/null || readlink "$claude_bin" 2>/dev/null)"
  [ -z "$active" ] && return 1
  case "$active" in
    "$path"/*|"$path") return 0 ;;
    *) return 1 ;;
  esac
}

refuse() {
  echo "REFUSED: $1 -- $2"
  log "REFUSED $1 -- $2"
}

for raw_path in "$@"; do
  # Resolve to an absolute real path; refuse if it doesn't resolve.
  path="$(cd "$(dirname "$raw_path")" 2>/dev/null && pwd -P)/$(basename "$raw_path")"
  if [ ! -e "$path" ]; then
    refuse "$raw_path" "path does not exist"
    continue
  fi

  home="$(cd ~ && pwd -P)"

  # Hard denylist: never touch these regardless of anything else.
  case "$path" in
    "$home"|/|/System*|/Applications|/Applications/*.app)
      refuse "$path" "top-level or system/app path, never auto-delete"
      continue
      ;;
  esac
  if [[ "$path" == */.git || "$path" == */.git/* ]]; then
    refuse "$path" "inside a .git directory"
    continue
  fi
  if [[ "$(basename "$path")" == terraform.tfstate* ]]; then
    refuse "$path" "terraform state file, never delete"
    continue
  fi

  # Allowlist: must match one known-safe, regenerable category.
  allowed=0
  reason=""
  case "$path" in
    */node_modules)
      allowed=1; reason="node_modules (regenerate: npm/pnpm/yarn install)" ;;
    */venv|*/.venv)
      allowed=1; reason="python venv (regenerate: pip install -r requirements.txt, or use requirements-freeze-backup.txt if one was taken)" ;;
    */.terraform/providers)
      allowed=1; reason="terraform provider cache (regenerate: terraform init)" ;;
    */__pycache__)
      allowed=1; reason="python bytecode cache (regenerates automatically)" ;;
    "$home"/.npm/_cacache|"$home"/.cache/uv|"$home"/Library/Caches/*|"$home"/.cache/*|"$home"/.bun/install/cache|"$home"/Library/pnpm/store*|"$home"/Library/Caches/pnpm/*)
      allowed=1; reason="package/build cache (regenerates on next install/build)" ;;
    "$home"/Library/Developer/Xcode/DerivedData|"$home"/Library/Developer/Xcode/DocumentationCache)
      allowed=1; reason="Xcode build/doc cache (Xcode rebuilds it on next build/index)" ;;
    "$home"/.local/share/claude/versions/*)
      if is_active_claude_version_dir "$path"; then
        refuse "$path" "this is the ACTIVE Claude Code version, refusing to delete"
        continue
      fi
      allowed=1; reason="old Claude Code version install (the CLI re-downloads versions as needed)" ;;
    "$home"/.Trash/*)
      allowed=1; reason="already in Trash -- user already chose to delete this" ;;
    *)
      allowed=0 ;;
  esac

  # Special case: "empty the Trash" means clearing its contents, not removing
  # the ~/.Trash directory itself (macOS expects it to exist).
  #
  # macOS requires the calling app to have Full Disk Access to *enumerate*
  # ~/.Trash -- without it, `find`/`ls` on the bare directory fail with
  # "Operation not permitted" but a script that only checks the item COUNT
  # afterward sees zero either way (empty dir, or access denied) and would
  # wrongly report success. Probe for that error explicitly before touching
  # anything, and again after, rather than trusting a zero count alone.
  if [ "$path" = "$home/.Trash" ]; then
    probe_err="$(find "$path" -mindepth 1 -maxdepth 1 2>&1 >/dev/null)"
    if [ -n "$probe_err" ]; then
      echo "REFUSED: $path -- cannot access Trash contents ($probe_err). This app likely needs Full Disk Access (System Settings > Privacy & Security > Full Disk Access) to empty the Trash programmatically. Empty it via Finder instead, or grant access and retry."
      log "REFUSED $path -- Trash inaccessible: $probe_err"
      continue
    fi
    before_count="$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$before_count" = "0" ]; then
      echo "SKIPPED: $path is already empty"
      log "SKIPPED $path already empty"
      continue
    fi
    size="$(du -sh -x "$path" 2>/dev/null | cut -f1)"
    find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
    remaining="$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$remaining" = "0" ]; then
      echo "DELETED: $path contents ($size freed) -- already in Trash, user already chose to delete this"
      log "DELETED $path contents ($size freed) -- emptied Trash"
    else
      echo "PARTIAL: $path ($remaining of $before_count items remain, may be in use or permission-protected)"
      log "PARTIAL $path ($remaining of $before_count items remain after emptying attempt)"
    fi
    continue
  fi

  if [ "$allowed" -ne 1 ]; then
    refuse "$path" "does not match any known-safe deletable category"
    continue
  fi

  size="$(du -sh -x "$path" 2>/dev/null | cut -f1)"
  rm -rf "$path"
  if [ -e "$path" ]; then
    echo "FAILED: $path (still exists after rm -rf)"
    log "FAILED $path (still exists)"
  else
    echo "DELETED: $path ($size freed) -- $reason"
    log "DELETED $path ($size freed) -- $reason"
  fi
done
