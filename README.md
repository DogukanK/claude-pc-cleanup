# pc-cleanup

A [Claude Code](https://claude.com/claude-code) skill that scans a macOS
machine for reclaimable disk space and cleans it up safely — the kind of
"disk almost full" problem every developer's Mac eventually runs into,
mostly from package manager caches, old build artifacts, and `node_modules`
piling up across projects.

Instead of guessing what's safe to delete, it:

1. **Scans** — a read-only pass over the usual suspects: `~/Library/Caches`,
   `~/.cache`, dev toolchain caches (npm/pnpm/uv/bun/cargo/go/cocoapods/
   homebrew/playwright), old Claude Code CLI versions, Xcode DerivedData,
   container/VM runtimes (Podman/Docker), iOS Simulator devices, the Trash,
   Homebrew's own cleanup candidates, Downloads, and — per project — every
   `node_modules` / `venv` / `.terraform/providers` it can find.
2. **Classifies** everything into three tiers: safe & fully regenerable,
   regenerable-but-needs-your-judgment (a running Podman VM, Downloads
   contents, etc.), and never-touch (`.git`, `terraform.tfstate`, `/System`,
   your home directory).
3. **Shows you the plan** — sizes, tiers, and *why* each item is safe
   (lockfile present, OS cache convention, already in Trash, etc.) — before
   touching anything.
4. **Only deletes what you approve**, through a guardrailed script that
   re-derives the safety rules in code, so a misread instruction can't
   accidentally delete something it shouldn't.

It's built to be run repeatedly — it logs what it frees over time to
`~/.claude/pc-cleanup-history.log` — rather than a one-off script.

## Why not just a shell script?

A fixed script can't tell a `node_modules` backed by a lockfile (trivially
safe to delete) from one that isn't, can't tell you *why* `~/Library/Caches`
is safe to clear, and can't have a conversation with you about the judgment
calls (a running Podman VM, a `venv` with no `requirements.txt`, files in
Downloads). That reasoning is the actual value here — the bundled scripts
just do the deterministic parts (measuring, and enforcing the guardrails on
delete) so the model doesn't have to reinvent them, and so a broken
guardrail is a script bug you can test for, not an instruction that quietly
stopped being followed.

## Install

```bash
git clone https://github.com/DogukanK/claude-pc-cleanup.git ~/.claude/skills/pc-cleanup
```

That's it — Claude Code loads skills from `~/.claude/skills/` automatically.
No build step, no dependencies beyond what's already on a normal Mac
(`bash`, `du`, `df`, `find`; optionally `brew`, `podman`/`docker`, `xcrun`
if you have them installed — the scan just skips what's not present).

### Update

```bash
cd ~/.claude/skills/pc-cleanup && git pull
```

### Uninstall

```bash
rm -rf ~/.claude/skills/pc-cleanup
```

## Use

Just talk to Claude Code naturally — no slash command to remember:

> "diskim doldu, gereksiz dosyaları temizler misin"
> "my Mac says storage is almost full, what's safe to delete?"
> "clean up my mac, running out of space"

It runs the scan itself (read-only, no need to approve that part), shows
you a tiered table with sizes, and asks which tier(s) or specific items you
want it to actually delete. Nothing is removed without that explicit
go-ahead — including when the request sounds like blanket permission
("delete everything unnecessary"), since deciding what "unnecessary"
actually means safely is the whole point.

## Safety model

- **Read-only by default.** `scripts/scan.sh` only runs `du`/`df`/`find`/`ls`.
- **Nothing is deleted without your explicit confirmation**, tier by tier
  or item by item — see `SKILL.md` for the full Phase 1-5 breakdown.
- **Deletion goes through `scripts/safe_delete.sh`**, which independently
  re-checks every path against an allowlist (`node_modules`, `venv`,
  `.terraform/providers`, package-manager caches, old CLI versions, Trash)
  and a denylist (`.git`, `terraform.tfstate*`, the active Claude Code
  version, your home directory, `/System`, `/Applications/*.app`) *in code*
  — not just in the instructions Claude is following. If it refuses
  something, that's the guardrail working as intended.
- **`scripts/selftest.sh`** is a regression test for those guardrails —
  useful if you fork this and change the scripts.
- Every deletion (or refusal) is logged with a timestamp to
  `~/.claude/pc-cleanup-history.log`.

## What it won't do

- Won't touch anything inside a `.git` directory or your actual source code.
- Won't touch `terraform.tfstate` / `.backup` files, ever.
- Won't delete `node_modules`/`venv`/`.terraform/providers` unless it found
  a lockfile/requirements file/`.terraform.lock.hcl` proving it's
  regenerable — no lockfile means it asks you instead of guessing.
- Won't decide what's junk in your Downloads folder for you.
- Won't try to work around macOS's Full Disk Access requirement for
  emptying the Trash — if it can't read `~/.Trash`, it says so honestly
  instead of assuming it's empty.

## Contributing

It's a plain-text `SKILL.md` plus three POSIX shell scripts — no build
step. `evals/evals.json` has the test prompts this was validated against
if you want to extend coverage or verify a change. PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
