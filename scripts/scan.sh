#!/bin/bash
# Read-only disk usage scan for macOS. Prints structured, labeled sections
# that the calling model classifies into cleanup tiers. Never deletes anything.
#
# Usage: scan.sh [project_root ...]
#   project_root: extra directories to scan for node_modules/venv/.terraform bloat.
#                 Defaults to a list of common dev-folder names under $HOME that exist.

set -uo pipefail

section() { printf '\n===== %s =====\n' "$1"; }

section "DISK SPACE (df -h)"
df -h / 2>/dev/null
df -h /System/Volumes/Data 2>/dev/null

section "HOME TOP LEVEL (du -sh -x, sorted)"
du -sh -x ~/* ~/.[a-zA-Z]* 2>/dev/null | sort -rh

section "~/Library BREAKDOWN"
du -sh -x ~/Library/* 2>/dev/null | sort -rh | head -20

section "~/Library/Application Support BREAKDOWN"
du -sh -x ~/Library/Application\ Support/* 2>/dev/null | sort -rh | head -20

section "~/Library/Caches BREAKDOWN"
du -sh -x ~/Library/Caches/* 2>/dev/null | sort -rh | head -20

section "~/.cache BREAKDOWN"
du -sh -x ~/.cache/* 2>/dev/null | sort -rh | head -20

section "~/Library/Developer (Xcode/Simulator) BREAKDOWN"
du -sh -x ~/Library/Developer/* 2>/dev/null | sort -rh
[ -d ~/Library/Developer/Xcode/DerivedData ] && du -sh -x ~/Library/Developer/Xcode/DerivedData 2>/dev/null
[ -d ~/Library/Developer/Xcode/Archives ] && du -sh -x ~/Library/Developer/Xcode/Archives 2>/dev/null
[ -d ~/Library/Developer/Xcode/iOS\ DeviceSupport ] && du -sh -x ~/Library/Developer/Xcode/iOS\ DeviceSupport 2>/dev/null
[ -d ~/Library/Developer/CoreSimulator/Devices ] && du -sh -x ~/Library/Developer/CoreSimulator/Devices 2>/dev/null

section "~/.local/share BREAKDOWN"
du -sh -x ~/.local/share/* 2>/dev/null | sort -rh

section "CLAUDE CODE VERSIONS (~/.local/share/claude/versions)"
if [ -d ~/.local/share/claude/versions ]; then
  CLAUDE_BIN="$(command -v claude 2>/dev/null)"
  ACTIVE_VERSION_DIR=""
  if [ -n "$CLAUDE_BIN" ] && [ -L "$CLAUDE_BIN" ]; then
    ACTIVE_VERSION_DIR="$(readlink -f "$CLAUDE_BIN" 2>/dev/null || readlink "$CLAUDE_BIN" 2>/dev/null)"
  fi
  echo "active_binary_resolves_to: ${ACTIVE_VERSION_DIR:-UNKNOWN (fall back to: claude --version, match version string to a directory name below)}"
  claude --version 2>/dev/null | sed 's/^/claude --version output: /'
  echo "installed_versions (sorted by mtime, newest first):"
  ls -1t ~/.local/share/claude/versions 2>/dev/null
  echo "per-version sizes:"
  du -sh -x ~/.local/share/claude/versions/* 2>/dev/null | sort -rh
else
  echo "(not found)"
fi

section "CLAUDE DESKTOP vm_bundles"
[ -d ~/Library/Application\ Support/Claude/vm_bundles ] && du -sh -x ~/Library/Application\ Support/Claude/vm_bundles/* 2>/dev/null

section "DEV TOOLCHAIN CACHES"
for d in \
  ~/.npm/_cacache ~/.cache/uv ~/Library/pnpm ~/Library/Caches/pnpm \
  ~/.cache ~/.bun ~/.cargo ~/.rustup ~/go/pkg/mod ~/.m2 ~/.gradle \
  ~/.pub-cache ~/Library/Caches/CocoaPods ~/Library/Caches/Homebrew \
  ~/Library/Caches/ms-playwright ~/.cache/puppeteer ~/.cache/codex-runtimes \
  ~/Library/Caches/go-build ~/Library/Caches/pip
do
  [ -e "$d" ] && du -sh -x "$d" 2>/dev/null
done | sort -rh

section "CONTAINER / VM RUNTIMES"
if command -v podman >/dev/null 2>&1; then
  echo "-- podman machine list --"
  podman machine list 2>/dev/null
fi
if command -v docker >/dev/null 2>&1; then
  echo "-- docker context / disk usage --"
  docker system df 2>/dev/null
fi
[ -d ~/.local/share/containers ] && du -sh -x ~/.local/share/containers/* 2>/dev/null | sort -rh

section "iOS SIMULATOR DEVICES"
if command -v xcrun >/dev/null 2>&1; then
  TOTAL_SIMS=$(xcrun simctl list devices 2>/dev/null | grep -c "(")
  UNAVAILABLE_SIMS=$(xcrun simctl list devices 2>/dev/null | grep -c "unavailable")
  echo "total_devices: $TOTAL_SIMS  unavailable_devices: $UNAVAILABLE_SIMS"
  echo "unavailable device lines (safe to delete, the runtime backing them is gone):"
  xcrun simctl list devices 2>/dev/null | grep "unavailable"
fi

section "TRASH (~/.Trash)"
if [ -d ~/.Trash ]; then
  # macOS blocks *enumerating* ~/.Trash without Full Disk Access, and that
  # failure is silent (empty output) exactly like an actually-empty Trash --
  # so check stderr explicitly instead of trusting a zero count on its own.
  PROBE_ERR=$(find ~/.Trash -mindepth 1 -maxdepth 1 2>&1 >/dev/null)
  if [ -n "$PROBE_ERR" ]; then
    echo "cannot_read: $PROBE_ERR (this app likely lacks Full Disk Access -- do not assume Trash is empty)"
  else
    ITEM_COUNT=$(find ~/.Trash -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    echo "item_count: $ITEM_COUNT"
    du -sh -x ~/.Trash 2>/dev/null
  fi
else
  echo "(no ~/.Trash found)"
fi

section "HOMEBREW CLEANUP (dry run, brew -n never deletes)"
if command -v brew >/dev/null 2>&1; then
  brew cleanup -n 2>/dev/null
else
  echo "(homebrew not installed)"
fi

section "DOWNLOADS (top items)"
du -sh -x ~/Downloads/* 2>/dev/null | sort -rh | head -15

section "DOWNLOADS (installer files: .dmg/.pkg/.msi/.exe, likely already installed)"
find ~/Downloads -maxdepth 3 -type f \( -iname "*.dmg" -o -iname "*.pkg" -o -iname "*.msi" -o -iname "*.exe" \) 2>/dev/null | while read -r f; do
  sz=$(du -sh -x "$f" 2>/dev/null | cut -f1)
  echo "$sz | $f"
done

section "SLEEP IMAGE / VAR FOLDERS (report only, never delete manually)"
[ -f /private/var/vm/sleepimage ] && ls -lh /private/var/vm/sleepimage 2>/dev/null
du -sh -x /private/var/folders 2>/dev/null

section "PROJECT BLOAT SCAN (node_modules / venv / .terraform providers / __pycache__)"
ROOTS=("$@")
if [ ${#ROOTS[@]} -eq 0 ]; then
  for candidate in ~/dev ~/Developer ~/Projects ~/projects ~/code ~/workspace ~/repos ~/Documents/GitHub; do
    [ -d "$candidate" ] && ROOTS+=("$candidate")
  done
fi
echo "scanned_roots: ${ROOTS[*]:-NONE FOUND}"

for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue

  echo "--- node_modules under $root ---"
  find "$root" -name node_modules -type d -prune 2>/dev/null | while read -r nm; do
    # Walk up from the package dir to $root looking for a lockfile, since
    # monorepo workspaces (pnpm/yarn/npm workspaces) keep one lockfile at the
    # repo root that also covers every nested package's node_modules.
    p=$(dirname "$nm")
    lock="NONE"
    walk="$p"
    while :; do
      for f in package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb; do
        if [ -f "$walk/$f" ]; then lock="$f (at $walk)"; fi
      done
      [ -n "${lock%NONE}" ] && break
      [ "$walk" = "$root" ] && break
      [ "$walk" = "/" ] && break
      walk=$(dirname "$walk")
    done
    sz=$(du -sh -x "$nm" 2>/dev/null | cut -f1)
    echo "$sz | $nm | lockfile=$lock"
  done

  echo "--- venv/.venv under $root ---"
  find "$root" \( -name venv -o -name .venv \) -type d -prune 2>/dev/null | while read -r v; do
    p=$(dirname "$v")
    reqfile="NONE"
    for f in requirements.txt pyproject.toml poetry.lock Pipfile.lock; do
      [ -f "$p/$f" ] && { reqfile="$f"; break; }
    done
    haspip="no"
    [ -x "$v/bin/pip" ] && haspip="yes"
    sz=$(du -sh -x "$v" 2>/dev/null | cut -f1)
    echo "$sz | $v | reqfile=$reqfile | pip_available_for_freeze_backup=$haspip"
  done

  echo "--- .terraform/providers under $root ---"
  find "$root" -path "*/.terraform/providers" -type d -prune 2>/dev/null | while read -r tp; do
    tfdir=$(dirname "$tp")
    lockfile="NONE"
    [ -f "$tfdir/../.terraform.lock.hcl" ] && lockfile=".terraform.lock.hcl (parent)"
    modroot=$(dirname "$tfdir")
    [ -f "$modroot/.terraform.lock.hcl" ] && lockfile=".terraform.lock.hcl"
    sz=$(du -sh -x "$tp" 2>/dev/null | cut -f1)
    statefiles=$(find "$modroot" -maxdepth 1 -name "terraform.tfstate*" 2>/dev/null | wc -l | tr -d ' ')
    echo "$sz | $tp | lockfile=$lockfile | sibling_tfstate_files=$statefiles (NEVER touch these)"
  done

  echo "--- __pycache__ under $root (always safe, always regenerable) ---"
  find "$root" -name __pycache__ -type d -prune -print0 2>/dev/null | xargs -0 du -sh -x -c 2>/dev/null | tail -1
done

section "SCAN COMPLETE"
echo "This script only reads and measures. Nothing was deleted."
