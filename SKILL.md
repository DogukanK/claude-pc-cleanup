---
name: pc-cleanup
description: Scan a macOS machine for reclaimable disk space and clean it up safely. Use this whenever the user reports low disk space, a "disk almost full" warning, wants to free up storage, asks to delete unnecessary/junk/system files, mentions "sistem verileri" (macOS's System Data category) taking up too much room, asks what's safe to delete on their Mac, wants to reclaim space from old node_modules/Docker or Podman images/build caches piled up across dev projects, or wants a recurring PC/disk cleanup routine — even if they never say the words "disk" or "clean up" outright. Always run the read-only scan first, present a tiered summary, and get explicit confirmation before deleting anything — never delete first and explain later.
---

# PC Cleanup (macOS)

Free up disk space by finding what is safe to delete, showing the user exactly
what that is and why it's safe, getting their explicit go-ahead, and only then
deleting it. This is a recurring maintenance task the user runs periodically —
optimize for a routine that is fast to run, trustworthy, and never surprises
them with something gone that they needed.

The core discipline: **almost everything on a dev machine that takes up a lot
of space is either a cache or a build artifact that something else can
regenerate.** The job is to prove that regenerability before suggesting
deletion, not to assume it.

## Phase 1 — Scan (read-only, always safe to run without asking)

Run the bundled scanner:

```bash
bash ~/.claude/skills/pc-cleanup/scripts/scan.sh [project_root ...]
```

With no arguments it auto-detects common dev folders (`~/dev`, `~/Developer`,
`~/Projects`, `~/code`, `~/workspace`, `~/repos`, `~/Documents/GitHub`) if they
exist. If the user mentions a specific projects folder that isn't one of
those, pass it explicitly.

The script only reads and measures — `du`/`df`/`find`/`ls`, nothing that
writes or deletes. It's safe to run proactively the moment this skill
triggers, before asking the user anything.

It prints labeled sections: overall disk space, top-level home directory
sizes, breakdowns of `~/Library` (Application Support, Caches, Developer)
and `~/.cache`, `~/.local/share`, installed Claude Code versions (with
which one is currently active), dev toolchain caches (npm/pnpm/uv/bun/
cargo/go/cocoapods/homebrew/playwright/puppeteer), container/VM runtimes
(Podman/Docker), iOS Simulator devices (including which specific ones are
`unavailable`), `~/.Trash` (item count and size), a Homebrew `cleanup -n`
dry run, Downloads folder contents (plus a separate pass for `.dmg`/`.pkg`/
`.msi`/`.exe` installer files specifically), and — per project root — every
`node_modules`, `venv`/`.venv`, and `.terraform/providers` directory it
found, each annotated with whether a lockfile/requirements file exists next
to it (walking up to the project root for monorepo workspaces, since one
lockfile at the repo root covers every nested package).

Read that output yourself and do the classification below — the script
deliberately doesn't judge, because "is this safe" depends on things like
whether a lockfile is actually present, which changes per machine.

One thing to watch for: macOS blocks *listing* `~/.Trash` from a script
unless the app running it has Full Disk Access, and that failure is
silent — it looks exactly like an empty Trash instead of raising an error
you'd notice. The scan script specifically checks for this and prints
`cannot_read: ...` instead of `item_count: 0` when it can't tell. If you
see that line, say so in the report (Trash may or may not have anything in
it, you genuinely don't know) rather than reporting Trash as empty.

## Phase 2 — Classify into tiers

Sort everything the scan found into three tiers. Don't go *looking* for
other things to delete outside what the scanner surfaced — but don't drop
anything the scanner *did* surface either, even if it doesn't match one of
the named examples below. A large directory the scan measured and you can't
place in any tier still belongs in the report; say what it is and make your
best call, rather than silently leaving it out. An item missing from the
report is worse than an item in the wrong tier — the user can't act on
something they never saw.

**Tier A — safe, fully regenerable, delete without much hesitation:**
- Old Claude Code versions in `~/.local/share/claude/versions/` — keep the
  currently active one (the scan output tells you which) plus one prior
  version as a fallback; every other version entry is Tier A. Each entry
  can be either a directory or a single executable file depending on the
  CLI's install format at the time — don't assume one or the other, `du`
  and `rm` both handle either fine.
- **Anything directly under `~/Library/Caches/` or `~/.cache/` is Tier A by
  default.** Those two directories exist specifically so that macOS and
  well-behaved Unix tools have a place to put data they can regenerate or
  redownload on demand — that's the OS-level contract, not something
  specific to any one tool. The scan's `~/Library/Caches BREAKDOWN` and
  `DEV TOOLCHAIN CACHES` sections list what's actually there on this
  machine; go through that list item by item rather than only mentioning
  the ones named below. Only pull something *out* of Tier A if you have a
  concrete reason to think it's not really disposable (e.g. it looks like
  an active login session/profile rather than a rebuildable cache).
  Common examples, so you recognize them for what they are: `~/.npm/_cacache`,
  `~/Library/pnpm`, `~/Library/Caches/pnpm`, `~/.cache/uv`, `~/.cache/puppeteer`,
  `~/Library/Caches/ms-playwright`, `~/.cache/codex-runtimes`,
  `~/Library/Caches/CocoaPods`, `~/Library/Caches/Homebrew`,
  `~/Library/Caches/go-build`, `~/Library/Caches/pip`.
- `~/Library/Developer/Xcode/DerivedData` and
  `~/Library/Developer/Xcode/DocumentationCache` — these live outside
  `~/Library/Caches` but are exactly the same kind of thing: Xcode rebuilds
  DerivedData from source on the next build and re-syncs DocumentationCache
  on its own. On a machine with real iOS/macOS development this is
  routinely several GB, so don't skip it just because it isn't under the
  `Caches` folder by name.
- `node_modules` where a lockfile exists (either directly next to it, or at
  a monorepo root — the scan output already resolved this for you). No
  lockfile anywhere up the tree → don't offer it as Tier A, ask the user
  instead (package.json alone doesn't pin versions, so a fresh install could
  silently change dependency versions).
- `.terraform/providers` where a `.terraform.lock.hcl` exists next to it.
  Only ever the `providers` subfolder — never the rest of `.terraform/`, and
  never anything named `terraform.tfstate*` (state lives next to, not inside,
  `.terraform/`, but double-check the scan's `sibling_tfstate_files` count
  before touching a project's `.terraform` directory at all).
- `__pycache__` — always safe, always regenerates, no lockfile check needed.
- `venv`/`.venv` where a `requirements.txt`, `pyproject.toml`, `poetry.lock`,
  or `Pipfile.lock` exists next to it.
- **`~/.Trash` contents.** Unlike everything else in this tier, these
  aren't a rebuildable cache — they're files the user already told macOS
  to delete by dragging them there. There's no "regenerating" them, but
  there's also no ambiguity about intent, which is exactly the property
  that makes something safe to default to Tier A here. Report the item
  count and total size; emptying it is equivalent to Finder's "Empty
  Trash".
- Old/unavailable iOS Simulator devices specifically — the scan lists
  which `simctl` entries are marked `unavailable` (their runtime was
  removed by an Xcode update). Those specific devices are Tier A: nothing
  can run on them anymore anyway. This is separate from the *available*
  simulator devices, which are Tier B (see below).
- Homebrew's own cleanup: if `brew` is installed, the scan's `brew cleanup -n`
  dry-run output lists exactly what `brew cleanup` (no `-n`) would remove —
  old formula/cask versions and the download cache. This is Homebrew's own
  well-tested cleanup command, not a path for `safe_delete.sh` to touch (see
  Phase 4).

**Tier B — regenerable but needs the user's judgment, or has live state:**
- `venv`/`.venv` with **no** requirements file next to it. Still offer it,
  but only after taking a backup first (see Phase 3) — the user may not
  remember exactly what was installed.
- Podman/Docker machines — especially if the scan shows one currently
  running. Deleting it removes every container and image inside; the user
  needs to actually want that, not just tolerate it.
- Claude Desktop's `vm_bundles` — regenerates by re-downloading (~10 GB),
  only worth it if the user isn't relying on Desktop's agent/VM mode today.
- iOS Simulator devices that are still available/usable — wipes simulator
  app data and settings. (The unavailable ones are Tier A, above.)
- Downloads folder contents — these are files the user put there on
  purpose at some point; list the biggest items but don't propose deleting
  specific ones yourself, let the user tell you what's junk. The one
  exception worth calling out explicitly (still Tier B, still their call,
  but worth a specific mention rather than burying it in the general list):
  installer files (`.dmg`/`.pkg`/`.msi`/`.exe`) the scan finds in Downloads
  are very often leftovers from an app that's already installed — point
  them out by name as likely candidates, without assuming that's true for
  every one of them.

**Tier C — never propose, never touch automatically:**
- Anything inside a `.git` directory, or tracked source files in general.
- `terraform.tfstate` / `terraform.tfstate.backup` (anywhere).
- Whole `/Applications/*.app` bundles, the home directory itself, or
  anything at `/System`.
- `/private/var/folders` — this is real disk usage and legitimately large,
  but it's macOS's own scratch space; the OS cleans it up on its own, and a
  reboot reliably reclaims a big chunk of it. Mention this as a "reboot will
  help" note in the report, don't try to delete files under it yourself.
- `/private/var/vm/sleepimage` — a system file macOS manages itself.

## Phase 3 — Confirm

Present a summary table (item, size, tier, one-line reversibility note),
grouped by tier, with a reclaimable-space subtotal per tier and a grand
total. This is the point of the whole exercise — the user is trusting you to
have already done the safety-checking in Phase 2, so make the table clear
enough that they can sanity-check your classification at a glance rather
than having to ask "wait, is X actually safe?"

Then ask, using your question tool, which tiers or specific items to delete.
Recommend Tier A as the default selection, but always let the user choose —
never assume, and never delete anything without an explicit answer to this
question. This holds even if the user's original request sounded like
blanket permission ("gereksiz dosyaları sil", "clean up my junk") — "junk"
is exactly the judgment call this skill exists to get right, so still show
the table and get a specific go-ahead before touching disk.

If you're running without any way to get an interactive answer (no user to
respond to a question), stop here. Present the scan and the tiered summary
and end the turn — do not proceed to Phase 4 on your own inference of what
the user probably wants.

For any Tier B `venv` with no requirements file that the user approves,
back it up first:

```bash
"<venv_path>/bin/pip" freeze > "<venv_parent_dir>/requirements-freeze-backup.txt"
```

If the venv has no `bin/pip` at all, say so and skip the backup — there's
nothing to freeze from, and the user should know that before you delete it.

## Phase 4 — Delete

Delete only what was approved, using the bundled guardrailed helper rather
than raw `rm -rf`:

```bash
bash ~/.claude/skills/pc-cleanup/scripts/safe_delete.sh <path> [<path> ...]
```

This script re-derives the safety checks in code (never touches `.git`,
`terraform.tfstate*`, the active Claude Code version, or anything outside
the known-safe categories from Phase 2) and refuses anything that doesn't
match, printing why. That's intentional redundancy: this skill runs
repeatedly across many future sessions, and a guardrail enforced in a script
is one that can't be accidentally skipped by an instruction getting
misread. If it refuses something you expected it to delete, that's a signal
to double-check your classification, not to route around it with a raw `rm`.
The one exception worth knowing about ahead of time: if it refuses to empty
`~/.Trash` citing a permission error, that's macOS requiring Full Disk
Access for programmatic access to that specific directory — tell the user
to empty it via Finder instead, or grant Full Disk Access to whatever app
is running this shell and retry. Don't try to work around it with `sudo` or
other tricks; it's a deliberate macOS privacy boundary, not a bug to route
around.

It logs every deletion (or refusal) with a timestamp and size to
`~/.claude/pc-cleanup-history.log`, so repeated runs build up a visible
history of what's been cleaned over time.

For anything approved that doesn't fit the script's categories, delete it
directly with the appropriate command — the helper script only covers the
path-based categories in Phase 2's Tier A/B lists, not a universal deletion
tool:
- Podman/Docker machine → `podman machine rm <name>` (stop it first if running)
- Claude Desktop `vm_bundles` → `rm -rf` (it re-downloads on next use)
- Available Simulator devices the user picked → `xcrun simctl delete <UDID>`
- Unavailable Simulator devices (Tier A) → `xcrun simctl delete unavailable`
  removes all of them in one go
- Homebrew cleanup (Tier A) → `brew cleanup` (no `-n`) — this is Homebrew's
  own command, doesn't go through `safe_delete.sh`
- A Downloads item the user specifically named → `rm -rf` on that exact path

## Phase 5 — Report

Show:
- `df -h` before and after, and the total freed.
- An itemized list of what was actually deleted and how much each freed.
- How to regenerate each thing, so the user isn't left wondering:
  - Claude Code versions → nothing to do, the CLI manages its own versions.
  - npm/pnpm/yarn caches, `node_modules` → `npm install` / `pnpm install` /
    `yarn install` in that project.
  - `uv`/`pip` caches → repopulate automatically on next install.
  - `venv` → `python3 -m venv venv && venv/bin/pip install -r requirements.txt`
    (or `-r requirements-freeze-backup.txt` if that's the backup you took).
  - `.terraform/providers` → `terraform init` in that directory.
  - `__pycache__` → nothing to do, Python recreates it.
  - Xcode `DerivedData`/`DocumentationCache` → nothing to do, Xcode rebuilds
    on the next build/index.
  - Homebrew cleanup, Trash → nothing to regenerate, these aren't caches.
  - Unavailable Simulator devices → nothing to do; if you want a device back
    you'd create a fresh one for the runtime you need.
- A reminder that `/private/var/folders` is best cleared by rebooting, not
  by manual deletion.
- If Trash couldn't be read (permission error, see Phase 4), say so plainly
  rather than reporting it as already handled.
- Append one line to `~/.claude/pc-cleanup-history.log` yourself summarizing
  this run (date, total freed, tiers acted on) if the deletions you ran
  didn't already log it individually via `safe_delete.sh` — e.g. for a
  Podman/Simulator/Homebrew action taken outside that script. This is what
  makes "how much have I actually freed over time" answerable next time the
  user runs this skill.

Keep this concise — a table plus a couple of regeneration notes, not an essay.

If `~/.claude/pc-cleanup-history.log` has entries from before this run,
mention the running total briefly (e.g. "this is the Nth time this has run;
X GB freed in total so far") — one line, not a full history dump. That's
the payoff of this being a recurring routine rather than a one-off.

## Maintenance

`scripts/selftest.sh` is a regression test for `safe_delete.sh`'s guardrails
(node_modules/venv/.terraform/__pycache__ get deleted, `.git`/tfstate/the
active Claude Code version/anything unrecognized gets refused). It only
touches a throwaway temp directory. Run it after editing either script:

```bash
bash ~/.claude/skills/pc-cleanup/scripts/selftest.sh
```

It's not part of the normal Phase 1-5 flow — it's for whoever (a future
session, most likely) modifies these scripts later, to catch a broken
guardrail before it ships rather than after.
