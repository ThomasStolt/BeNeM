# BeNeM Monorepo Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the `ThomasStolt/BeNeM` repository into a monorepo containing `ios/`, `middleware/` (with full `bhnm-apns` history), `pwa/` (scaffold), and `shared/` (specs), using nine commits with two verification gates and no remote push until all gates pass.

**Architecture:** Explicit, auditable `git mv` commands grouped by destination; `git filter-repo` for per-file-history-preserving middleware import; staged commits with a pre-work safety tag for rollback; `CLAUDE.md` split that preserves the accumulated iOS context by moving it to `ios/CLAUDE.md` rather than discarding.

**Tech Stack:** git (with `git filter-repo` installed via Homebrew), Xcode command-line tools (`xcodebuild`), Python/FastAPI (middleware smoke test), macOS shell.

**Spec:** `docs/superpowers/specs/2026-04-05-monorepo-restructure-design.md`

**Canonical repo path used throughout:** `/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM` (the `~/OneDrive/Documents/Github/BeNeM` path is a symlink to this and may be used interchangeably).

---

## Task 0: Preflight and safety setup

**Purpose:** Install required tools, verify environment, create safety tag/branch before touching anything.

**Files:**
- None (pure git + shell)

- [ ] **Step 0.1: Verify OneDrive sync is paused**

Ask the user to confirm that OneDrive sync is paused (from the OneDrive menu bar → Settings → Pause syncing → At least 2 hours). This must remain paused until after Task 9.

Expected: user confirms "paused" before proceeding.

- [ ] **Step 0.2: Confirm working directory and clean state**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
git status
git rev-parse --abbrev-ref HEAD
git remote -v
```

Expected output:
- `git status` → "nothing to commit, working tree clean" (must be clean — untracked files should be none except those we know about)
- Current branch: `main`
- Remote `origin` → `https://github.com/ThomasStolt/BeNeM.git`

If the working tree is not clean, STOP and investigate. Do not proceed.

- [ ] **Step 0.3: Verify `git filter-repo` is installed**

Run:
```bash
which git-filter-repo || echo "NOT INSTALLED"
```

If output is `NOT INSTALLED`, install it:
```bash
brew install git-filter-repo
```

Then re-run `which git-filter-repo` and expect a path like `/opt/homebrew/bin/git-filter-repo` or `/usr/local/bin/git-filter-repo`.

- [ ] **Step 0.4: Verify `bhnm-apns` local clone exists and is clean**

```bash
cd ~/OneDrive/Documents/Github/bhnm-apns
git status
git rev-parse --abbrev-ref HEAD
ls -1 main.py 2>/dev/null && echo "main.py present"
cd -
```

Expected:
- `git status` → "nothing to commit, working tree clean"
- Current branch: `main`
- `main.py present`

If the bhnm-apns working tree is not clean, STOP. The import procedure operates on a clone and will preserve whatever state is committed — uncommitted changes would be lost.

- [ ] **Step 0.5: Create safety tag and backup branch**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
git tag pre-monorepo-restructure
git branch backup/pre-monorepo
git tag | grep pre-monorepo-restructure
git branch | grep pre-monorepo
```

Expected: both commands print the tag/branch name confirming creation.

**Rollback at any point in Tasks 1–8:**
```bash
git reset --hard pre-monorepo-restructure
```

---

## Task 1: Create monorepo subdirectories (commit 1 of 9)

**Purpose:** Create the four top-level subdirectories plus needed sub-paths. Use `.gitkeep` files only where directories would otherwise be empty (git does not track empty dirs).

**Files:**
- Create: `ios/.gitkeep`, `middleware/.gitkeep`, `pwa/.gitkeep`, `pwa/src/.gitkeep`, `shared/.gitkeep`, `ios/docs/.gitkeep`

Note: the `.gitkeep` files in `ios/`, `middleware/`, `shared/`, and `ios/docs/` are temporary — they will be removed implicitly by subsequent `git mv` operations populating those directories. `pwa/src/.gitkeep` is permanent until the PWA is scaffolded.

- [ ] **Step 1.1: Create directories**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
mkdir -p ios/docs middleware pwa/src shared
```

- [ ] **Step 1.2: Add `.gitkeep` files**

```bash
touch ios/.gitkeep ios/docs/.gitkeep middleware/.gitkeep pwa/.gitkeep pwa/src/.gitkeep shared/.gitkeep
```

- [ ] **Step 1.3: Stage and verify**

```bash
git add ios/.gitkeep ios/docs/.gitkeep middleware/.gitkeep pwa/.gitkeep pwa/src/.gitkeep shared/.gitkeep
git status
```

Expected: six new files staged, no other changes.

- [ ] **Step 1.4: Commit**

```bash
git commit -m "chore: create monorepo subdirectories

Create ios/, middleware/, pwa/src/, shared/, and ios/docs/ as empty
directories with .gitkeep placeholders. Subsequent commits populate
them and remove the .gitkeep files where no longer needed."
```

Expected: commit succeeds, `git log --oneline -1` shows the new commit.

---

## Task 2: Move iOS sources and tooling into `ios/` (commit 2 of 9)

**Purpose:** Relocate everything iOS-specific into `ios/`. Uses `git mv` for tracked files and plain `mv` for the gitignored `build.local.sh`. Each command is explicit and quoted to handle filenames with spaces inside moved directories.

**Files moved to `ios/`** (12 items, 11 tracked + 1 gitignored):
- `BeNeM/` (Swift source tree)
- `BeNeM.xcodeproj`
- `build_and_deploy.sh`
- `build.local.sh.example`
- `build.local.sh` (gitignored — plain `mv`)
- `generate_benem_link.py`
- `.env.template`
- `scripts/`
- `images/`
- `SETUP.md`
- `CHANGELOG.md`
- `docs/user-guide.html` → `ios/docs/user-guide.html`

- [ ] **Step 2.1: Remove the placeholder `.gitkeep` files about to be populated**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
git rm ios/.gitkeep ios/docs/.gitkeep
```

Expected: two deletions staged.

- [ ] **Step 2.2: `git mv` all tracked iOS files and directories**

```bash
git mv BeNeM ios/
git mv BeNeM.xcodeproj ios/
git mv build_and_deploy.sh ios/
git mv build.local.sh.example ios/
git mv generate_benem_link.py ios/
git mv .env.template ios/
git mv scripts ios/
git mv images ios/
git mv SETUP.md ios/
git mv CHANGELOG.md ios/
git mv docs/user-guide.html ios/docs/user-guide.html
```

Expected: each command completes silently. If any fails with "fatal: bad source", STOP — a file is not tracked or the path is wrong; do not proceed.

- [ ] **Step 2.3: Plain `mv` for gitignored `build.local.sh`**

```bash
if [ -f build.local.sh ]; then
  mv build.local.sh ios/build.local.sh
  echo "moved build.local.sh"
else
  echo "build.local.sh not present — skipping"
fi
```

Expected: either "moved build.local.sh" or "build.local.sh not present — skipping". The file may not exist if the user has never created it locally. The gitignore pattern `build.local.sh` is a bare pattern matching any depth, so `ios/build.local.sh` remains ignored without modification.

- [ ] **Step 2.4: Verify the move**

```bash
git status --short
ls -1 ios/ | head -30
```

Expected in `git status`:
- `R  BeNeM.xcodeproj/... -> ios/BeNeM.xcodeproj/...`
- `R  BeNeM/... -> ios/BeNeM/...`
- `R  CHANGELOG.md -> ios/CHANGELOG.md`
- …etc for every `git mv`
- `D  ios/.gitkeep`
- `D  ios/docs/.gitkeep`

Expected in `ls ios/`: all moved files and directories visible.

- [ ] **Step 2.5: Commit**

```bash
git commit -m "chore: move iOS sources and tooling into ios/

Relocate BeNeM Xcode project, Swift source tree, build scripts,
scripts/, images/, generate_benem_link.py, .env.template, SETUP.md,
CHANGELOG.md, and user-guide.html into the ios/ subdirectory of
the monorepo.

Uses git mv for all tracked files. build.local.sh is gitignored
and was relocated with plain mv; the existing .gitignore pattern
continues to match at the new depth."
```

---

## Task 3: Move shared docs into `shared/` and delete `test.json` (commit 3 of 9)

**Purpose:** Relocate cross-cutting documentation (product, architecture, credentials, BHNM API reference) into `shared/`. Delete the gitignored `test.json` scratch file. The file `docs/internal/bhnm-timeseries-metrics-api.md` is gitignored at source but is moved to `shared/` and its gitignore rule is removed in commit 8 — for this commit we simply stage it at the new location with `git add`.

**Files moved to `shared/`:**
- `BHNM_API_REFERENCE.md` (tracked)
- `docs/PRD-BeNeM-Product-Requirements-Document.md` (tracked)
- `docs/architecture.svg` (tracked)
- `docs/credentials-and-keys-overview.md` (tracked)
- `docs/internal/bhnm-timeseries-metrics-api.md` (gitignored — plain `mv` + `git add -f`)

**Files deleted:**
- `test.json` (gitignored scratch — plain `rm`)
- `M1BJKI1M3C52.png` (if present, gitignored, user can delete manually; not handled by this plan)

- [ ] **Step 3.1: Remove the placeholder `shared/.gitkeep`**

```bash
git rm shared/.gitkeep
```

- [ ] **Step 3.2: `git mv` tracked shared docs**

```bash
git mv BHNM_API_REFERENCE.md shared/
git mv docs/PRD-BeNeM-Product-Requirements-Document.md shared/
git mv docs/architecture.svg shared/
git mv docs/credentials-and-keys-overview.md shared/
```

Expected: four rename entries in `git status`.

- [ ] **Step 3.3: Move the gitignored internal doc and force-stage it**

```bash
if [ -f docs/internal/bhnm-timeseries-metrics-api.md ]; then
  mv docs/internal/bhnm-timeseries-metrics-api.md shared/bhnm-timeseries-metrics-api.md
  git add -f shared/bhnm-timeseries-metrics-api.md
  rmdir docs/internal 2>/dev/null || true
else
  echo "docs/internal/bhnm-timeseries-metrics-api.md not present — skipping"
fi
```

Expected: either the file is staged via `git add -f` (necessary because the source path is still matched by the `docs/internal/` ignore rule at this point), or the skip message appears if the file is not present locally.

- [ ] **Step 3.4: Delete `test.json`**

```bash
if [ -f test.json ]; then
  rm test.json
  echo "removed test.json"
else
  echo "test.json not present — skipping"
fi
```

Expected: "removed test.json" (most likely) or skip message. No git action needed because `test.json` is gitignored and therefore not tracked.

- [ ] **Step 3.5: Verify**

```bash
git status --short
ls -1 shared/
ls docs/ 2>/dev/null
```

Expected:
- `git status` shows four renames into `shared/` + the force-added `bhnm-timeseries-metrics-api.md` + the `shared/.gitkeep` deletion
- `ls shared/` shows 5 files
- `ls docs/` shows only `superpowers/` (and possibly the now-empty `internal/` if it wasn't removed — safe either way)

- [ ] **Step 3.6: Commit**

```bash
git commit -m "chore: move shared docs and API reference into shared/

Relocate BHNM_API_REFERENCE.md, product requirements, architecture
diagram, credentials overview, and the previously-gitignored BHNM
timeseries API notes into shared/. The timeseries API doc is now
tracked (the ignore rule that hid it is removed in commit 8).

Also deletes test.json, a gitignored scratch file no longer needed."
```

---

## Task 4: Split `CLAUDE.md` into monorepo root and `ios/` (commit 4 of 9) — Gate A

**Purpose:** Preserve the accumulated iOS context by moving `CLAUDE.md` to `ios/CLAUDE.md` with targeted edits, then write a new thin monorepo-overview `CLAUDE.md` at the repo root. After commit: run `xcodebuild -list` (Gate A) to confirm the Xcode project still resolves from its new location before proceeding to the irreversible middleware import.

**Files:**
- Create: `ios/CLAUDE.md` (via `git mv` from root, then edited)
- Create: `CLAUDE.md` (new file at repo root)

- [ ] **Step 4.1: Move the existing `CLAUDE.md` into `ios/`**

```bash
git mv CLAUDE.md ios/CLAUDE.md
```

- [ ] **Step 4.2: Edit `ios/CLAUDE.md` — change the title**

Use the Edit tool to change line 1:
- `old_string`: `# BeNeM – Claude Code Context`
- `new_string`: `# BeNeM iOS – Claude Code Context`

- [ ] **Step 4.3: Edit `ios/CLAUDE.md` — add pointer to monorepo root**

Use the Edit tool to insert a pointer paragraph after the first non-title paragraph:

- `old_string`:
```
BeNeM (Be Netreo Mobile) is an iOS app built with Swift/SwiftUI for monitoring network devices and incidents via the **BMC Helix Network Management** (BHNM) API.

> **Naming note:**
```

- `new_string`:
```
BeNeM (Be Netreo Mobile) is an iOS app built with Swift/SwiftUI for monitoring network devices and incidents via the **BMC Helix Network Management** (BHNM) API.

> Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules, `../middleware/CLAUDE.md` for the push middleware, and `../shared/` for API contracts and feature specs.

> **Naming note:**
```

- [ ] **Step 4.4: Edit `ios/CLAUDE.md` — replace Push Notifications section with iOS-scoped version**

The current Push Notifications section contains both producer-side (middleware architecture, deployment, auth) and consumer-side (iOS AppDelegate, payload handling) content. Replace it so only the iOS-consumer content remains; producer content moves to `middleware/CLAUDE.md` in Task 6.

Use the Edit tool:

- `old_string`:
```
## Push Notifications

BeNeM receives push notifications via a companion Python middleware (`bhnm-apns`) — a Docker container deployable to any cloud provider or self-hosted server.

### Architecture
```
BHNM Incident → Webhook → bhnm-apns middleware → APNs → iPhone
```

- **Middleware repo:** `github.com/ThomasStolt/bhnm-apns`
- **Deployed at:** `https://bhnm-apns.hurrikap.org` (Linode Nanode, Caddy handles TLS)
- **APNs environment:** sandbox (development builds), production for App Store
- **AppStorage keys:**
  - `push_middleware_url` — middleware base URL, configurable in Settings → Push Notifications
  - `push_middleware_secret` — shared secret for authenticating requests to the middleware

### Authentication
All requests to the middleware (`/register` and `/webhook`) require authentication via:
- **Header:** `X-Webhook-Token: <secret>` (used by BeNeM for `/register`)
- **Query param:** `?secret=<secret>` (used by BHNM for `/webhook`)

Both are accepted; the secret must match `WEBHOOK_SECRET` in the middleware's `.env`.

### iOS Side
```

- `new_string`:
```
## Push Notifications (iOS consumer side)

The iOS app receives push notifications via the `bhnm-apns` middleware.
See `../middleware/CLAUDE.md` for middleware-side details (deployment,
auth, APNs routing) and `../CLAUDE.md` for the cross-cutting architecture.

### AppStorage keys (iOS-side config)
- `push_middleware_url` — middleware base URL, configurable in Settings → Push Notifications
- `push_middleware_secret` — shared secret for authenticating requests to the middleware (sent as `X-Webhook-Token` header on `/register`)

### iOS Side
```

- [ ] **Step 4.5: Write the new repo-root `CLAUDE.md`**

Use the Write tool to create `/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/CLAUDE.md` with this exact content:

```markdown
# BeNeM Monorepo

BeNeM is a network monitoring and incident alerting app built on top of
**BMC Helix Network Management (BHNM)**. Its primary function is delivering
timely, reliable push notifications to engineers when incidents occur.

> **Naming note:** BHNM was formerly known as **Netreo**. Swift type names
> (`NetreoAPIService`, `NetreoIncident`, `NetreoDevice`, `NetreoAPIConfiguration`)
> and AppStorage keys (`netreo_base_url`, `netreo_api_key`, etc.) still use
> the legacy prefix for backwards compatibility. This applies across `ios/`
> and any future code that talks to BHNM.

## Structure

| Path | Purpose |
|---|---|
| `ios/` | Native Swift/SwiftUI iOS app. Primary platform. Distributed via App Store / TestFlight. |
| `middleware/` | Python/FastAPI service. Handles BHNM webhook ingestion and APNs / Web Push delivery. |
| `pwa/` | Progressive Web App (React/TypeScript), targeting Android via Web Push. Not yet scaffolded. |
| `shared/` | Specifications and documentation. Not deployed. Source of truth for feature parity and API contracts. |
| `docs/superpowers/` | Brainstorming specs and implementation plans (Claude Code). |

## Platform Strategy

The full decision record is in `shared/DECISION.md` (April 2026). Summary:

- **iOS native (Swift)** is the lead platform and the authoritative push delivery channel (APNs with Time Sensitive entitlement support).
- **PWA (React/TypeScript)** targets Android users via Web Push, and serves as a web dashboard for desktop/browser access. **iOS users of the PWA are directed to install the native app** — iOS Web Push is unreliable and EU-politically-unstable.
- A **single Python/FastAPI middleware** delivers push to both iOS (APNs `.p8`) and Android PWA (VAPID Web Push).

## Feature Parity Rule

Features are implemented on `ios/` first. As `pwa/` matures, features land
on both platforms unless explicitly marked platform-specific in
`shared/feature-spec.md`.

**Always update `shared/feature-spec.md` before or alongside implementation.**

## Push Notification Architecture

```
BHNM Incident → Webhook → bhnm-apns middleware → APNs (iOS) / Web Push (Android) → device
```

- Middleware (producer): see `middleware/CLAUDE.md`
- iOS consumer: see `ios/CLAUDE.md`
- PWA consumer: see `pwa/CLAUDE.md` (stub)
- Cross-platform payload contract: `shared/push-payload-spec.md`

Do NOT attempt to implement iOS-style Critical Alerts or Time Sensitive notifications in the PWA — the Web Push API does not support them on iOS.

## Sessions

- **Cross-platform feature work** (spans ios + middleware + pwa): open Claude Code from the repo root.
- **iOS-specific deep dives:** open from `ios/`.
- **Middleware-specific work:** open from `middleware/`.
- **PWA-specific work:** open from `pwa/`.

Always commit before switching session context.

## Minimum BHNM version

**26.1.02.** The iOS app uses UID-based device identity, pagination,
model/serial fields, and interface details — all require 26.1.01+.

## API

All BHNM API endpoints used by BeNeM are documented in
`shared/BHNM_API_REFERENCE.md` and (for the narrower subset currently
consumed) `shared/api-spec.md`.
```

- [ ] **Step 4.6: Stage and verify the edits**

```bash
git add CLAUDE.md ios/CLAUDE.md
git status --short
head -20 ios/CLAUDE.md
head -20 CLAUDE.md
```

Expected:
- `git status`: one rename (`CLAUDE.md -> ios/CLAUDE.md`) with modifications, plus the new root `CLAUDE.md`
- `head ios/CLAUDE.md` shows the new title and pointer paragraph
- `head CLAUDE.md` shows the new monorepo root content

- [ ] **Step 4.7: Commit**

```bash
git commit -m "chore: split CLAUDE.md into monorepo root and ios/

Move existing root CLAUDE.md to ios/CLAUDE.md with minor edits (title,
pointer to monorepo root, Push Notifications section scoped to iOS
consumer side — producer-side content will land in middleware/CLAUDE.md
in a later commit).

Write a new thin root CLAUDE.md describing the monorepo structure,
platform strategy (summarising shared/DECISION.md), feature parity
rule, push architecture overview, session guidance, minimum BHNM
version, and API reference pointers."
```

- [ ] **Step 4.8: GATE A — verify the Xcode project resolves from its new location**

```bash
cd ios
xcodebuild -list -project BeNeM.xcodeproj
cd ..
```

Expected output: a clean listing of targets, build configurations, and schemes (e.g., `Targets: BeNeM`, `Build Configurations: Debug, Release`, `Schemes: BeNeM`). No errors about missing files or unresolved paths.

**If Gate A fails** (e.g., `xcodebuild` reports missing files or a malformed project):
1. Do NOT proceed to Task 5 (the middleware import is the hardest step to back out of).
2. Read the error carefully — most likely cause is an absolute path in `project.pbxproj` that was resolvable at the old root but not at `ios/`.
3. Rollback: `git reset --hard pre-monorepo-restructure`
4. Investigate the absolute path(s) in `BeNeM.xcodeproj/project.pbxproj`, fix them in a separate preparatory commit on a branch, then restart from Task 0.

**Do not proceed to Task 5 until Gate A passes.**

---

## Task 5: Import `bhnm-apns` middleware history (commit 5 of 9)

**Purpose:** Bring the full `bhnm-apns` repository into `middleware/` with per-file history preserved via `git filter-repo`. This operates on a throwaway clone — the user's real `bhnm-apns` working copy and the GitHub remote are both untouched.

**Files:**
- Creates (from import): every file currently in `~/OneDrive/Documents/Github/bhnm-apns/` appears under `middleware/` — notably `middleware/main.py`, `middleware/apns.py`, `middleware/config.py`, `middleware/database.py`, `middleware/docker-compose.yml`, `middleware/Dockerfile`, `middleware/Caddyfile`, `middleware/CLAUDE.md`, `middleware/README.md`, `middleware/CHANGELOG.md`, `middleware/LICENSE`, `middleware/.gitignore`, `middleware/benem-admin/`, plus `middleware/.superpowers/` (see Step 5.6 cleanup).

- [ ] **Step 5.1: Remove the placeholder `middleware/.gitkeep`**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
git rm middleware/.gitkeep
```

- [ ] **Step 5.2: Clone `bhnm-apns` to a temp directory**

```bash
WORK=$(mktemp -d)
echo "WORK=$WORK"
git clone ~/OneDrive/Documents/Github/bhnm-apns "$WORK/bhnm-apns"
cd "$WORK/bhnm-apns"
git log --oneline | wc -l
```

Expected: a number > 0 — the total commit count of bhnm-apns. Remember this number; after import the monorepo log should show at least this many additional commits.

- [ ] **Step 5.3: Rewrite the clone so every path lives under `middleware/`**

```bash
cd "$WORK/bhnm-apns"
git filter-repo --to-subdirectory-filter middleware
ls -1
```

Expected after `ls -1`: a single `middleware/` directory containing all files that were previously at the root. If anything other than `middleware/` appears at the root, the filter-repo command failed — STOP and investigate.

- [ ] **Step 5.4: Fetch the rewritten history into the monorepo and merge**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
git remote add middleware-import "$WORK/bhnm-apns"
git fetch middleware-import
git merge --allow-unrelated-histories middleware-import/main \
  -m "chore: import bhnm-apns middleware history into middleware/"
git remote remove middleware-import
```

Expected:
- `git fetch` reports fetching a number of commits matching (or close to) the count from Step 5.2.
- `git merge` succeeds with no conflicts. The merge commit message is the one provided.
- `git remote remove` is silent.

**If the merge reports conflicts** (highly unlikely since paths are disjoint): STOP. Do not force the merge. Abort with `git merge --abort`, reset to `pre-monorepo-restructure`, and investigate.

- [ ] **Step 5.5: Commit the `.gitkeep` removal from Step 5.1**

The merge commit in 5.4 already folded the imported tree. Step 5.1 staged `middleware/.gitkeep` deletion, but it was part of the pre-merge index. Check status:

```bash
git status --short
```

If `middleware/.gitkeep` still shows as staged-deleted (it should, since the merge adds new files but doesn't touch the staged deletion), finalize it with a small follow-up commit:

```bash
git commit -m "chore: remove middleware/.gitkeep placeholder (superseded by import)"
```

If the status is clean (the merge absorbed the deletion automatically), skip this commit — note this as a deviation from the 9-commit count in the commit log.

- [ ] **Step 5.6: Clean up `middleware/.superpowers/` if imported**

```bash
if [ -d middleware/.superpowers ]; then
  git rm -rf middleware/.superpowers
  git commit -m "chore: remove imported middleware/.superpowers (tool cache, not source)"
fi
```

This is not counted as a numbered commit; it's a housekeeping follow-up to Task 5.

- [ ] **Step 5.7: Verify middleware files and per-file history**

```bash
ls middleware/main.py
git log --oneline --follow middleware/main.py | head -10
rm -rf "$WORK"
```

Expected:
- `ls middleware/main.py` prints the path (file exists).
- `git log --follow` prints at least a few commits from the original bhnm-apns history with their original messages and authors. If only one commit appears (the merge), `filter-repo` did not rewrite correctly — STOP and reset.
- `rm -rf "$WORK"` silently removes the temp clone.

---

## Task 6: Add `middleware/CLAUDE.md` (replace imported) and `pwa/CLAUDE.md` (commit 6 of 9)

**Purpose:** The `bhnm-apns` import brought in its own `middleware/CLAUDE.md`. Replace it with a monorepo-aware version that absorbs the producer-side push architecture content from the old root `CLAUDE.md`. Also create `pwa/CLAUDE.md` as a stub for future PWA work.

**Files:**
- Modify/replace: `middleware/CLAUDE.md` (imported from bhnm-apns; overwritten)
- Create: `pwa/CLAUDE.md` (stub)

- [ ] **Step 6.1: Inspect the imported `middleware/CLAUDE.md`**

```bash
cat middleware/CLAUDE.md
```

Expected: some content from the bhnm-apns project. Review it to see if there is any runtime/operational detail **not** already captured in the new content written in Step 6.2 (e.g., environment variable names, deployment quirks, unusual dependencies). If there is, note it — you will merge it into the new content rather than losing it.

- [ ] **Step 6.2: Replace `middleware/CLAUDE.md` with monorepo-aware content**

Use the Write tool to overwrite `/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/middleware/CLAUDE.md` with the following content. If Step 6.1 surfaced any unique operational details worth preserving, add them under a "Runtime notes" subsection before the final "## BHNM API" line.

```markdown
# BeNeM Middleware (bhnm-apns)

Python / FastAPI service. Receives BHNM webhook events and delivers push
notifications to iOS (APNs) and Android / PWA (Web Push).

> Part of the BeNeM monorepo. See `../CLAUDE.md` for the cross-cutting
> architecture and `../shared/push-payload-spec.md` for the payload
> contract shared with consumers.

## Key facts

- **Runtime:** Python / FastAPI
- **Repo origin:** merged from `github.com/ThomasStolt/bhnm-apns` with full per-file history preserved (April 2026 monorepo restructure)
- **Deployed at:** `https://bhnm-apns.hurrikap.org` (Linode Nanode, Caddy terminates TLS)
- **APNs:** `.p8` Auth Key (stored outside the repo, injected via environment variable)
- **Web Push:** VAPID key pair (stored outside the repo, injected via environment variable)
- **Dual APNs environment:** the middleware routes per-device-token to sandbox or production APNs endpoints (see `apns.py`)

## Authentication

All requests to `/register` and `/webhook` require authentication via:

- **Header:** `X-Webhook-Token: <secret>` (used by the iOS app for `/register`)
- **Query param:** `?secret=<secret>` (used by BHNM for `/webhook`)

Both are accepted; the secret must match `WEBHOOK_SECRET` in the middleware's `.env`.

## Endpoints

| Endpoint | Purpose | Consumer |
|---|---|---|
| `POST /register` | Register an APNs device token (and metadata) with the middleware | iOS app (`AppDelegate`) |
| `POST /webhook` | Receive a BHNM incident event and fan out push notifications | BHNM |

## Push payload contract

The APNs custom-data payload is:

```json
{ "aps": { "alert": {...}, "sound": "default" }, "incident_id": "<id>" }
```

All notification payload types (current and future) are defined in
`../shared/push-payload-spec.md`. When adding a new notification type,
update that spec first, then implement here.

## Security reminders

- Never commit `.p8`, `.pem`, or VAPID private keys. The root `.gitignore` blocks the obvious patterns but the primary defense is keeping keys outside the repo and injecting via environment.
- The BHNM API key used by the middleware is a separate credential from the iOS app's BHNM API key; both should be rotated independently.

## BHNM API

Endpoint contracts are in `../shared/BHNM_API_REFERENCE.md` (full reference)
and `../shared/api-spec.md` (narrower subset actively consumed).
```

- [ ] **Step 6.3: Write `pwa/CLAUDE.md`**

Use the Write tool to create `/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/pwa/CLAUDE.md` with this exact content:

```markdown
# BeNeM PWA

React/TypeScript Progressive Web App. Targets Android users via Web Push.
iOS users are directed to the native app for reliable push notifications.

> Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules,
> `../shared/feature-spec.md` for the canonical feature list, and
> `../shared/push-payload-spec.md` for the notification payload contract.

> **Status:** Not yet scaffolded. This file is a placeholder. When PWA work
> begins, expand this with framework/library choices, build tooling, and
> deployment target.

## Key facts (target state)

- **Web Push:** VAPID-based, delivered via `../middleware/`
- **iOS caveat:** Push on iOS is unreliable (subscription expiry bug, no Time Sensitive entitlement) and EU-regulatorily unstable. Do NOT position Web Push as the primary alert channel for iOS users. Display a prominent banner to iOS users recommending the native app for incident alerts. See `../shared/DECISION.md` for the full rationale.

## Feature spec

Refer to `../shared/feature-spec.md`. PWA-specific behaviour is marked there.
```

- [ ] **Step 6.4: Remove the placeholder `pwa/.gitkeep` (but keep `pwa/src/.gitkeep`)**

```bash
git rm pwa/.gitkeep
# pwa/src/.gitkeep stays — src/ is still empty and needs a placeholder
```

- [ ] **Step 6.5: Stage and verify**

```bash
git add middleware/CLAUDE.md pwa/CLAUDE.md
git status --short
```

Expected: `middleware/CLAUDE.md` as modified, `pwa/CLAUDE.md` as new, `pwa/.gitkeep` as deleted.

- [ ] **Step 6.6: Commit**

```bash
git commit -m "docs: replace middleware/CLAUDE.md and add pwa/CLAUDE.md

Replace the imported middleware/CLAUDE.md with a monorepo-aware version
that absorbs the producer-side push architecture content stripped from
the old root CLAUDE.md in the earlier split. Add pwa/CLAUDE.md as a
placeholder for future PWA scaffolding work."
```

---

## Task 7: Add `shared/` specification stubs (commit 7 of 9)

**Purpose:** Populate `shared/` with the stub spec files — `DECISION.md` (verbatim), `feature-spec.md`, `push-payload-spec.md`, `api-spec.md`. These are intentionally minimal; the principle is spec-first going forward, not retroactive reverse-engineering.

**Files:**
- Create: `shared/DECISION.md` (copied verbatim from `~/Downloads/DECISION.md`)
- Create: `shared/feature-spec.md`
- Create: `shared/push-payload-spec.md`
- Create: `shared/api-spec.md`

- [ ] **Step 7.1: Copy `DECISION.md` verbatim**

```bash
cp ~/Downloads/DECISION.md shared/DECISION.md
diff ~/Downloads/DECISION.md shared/DECISION.md && echo "identical"
```

Expected: "identical" — the files must match byte-for-byte.

- [ ] **Step 7.2: Write `shared/feature-spec.md`**

Use the Write tool to create `/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/shared/feature-spec.md` with this exact content:

```markdown
# BeNeM Feature Specification

This is the canonical feature list for BeNeM. Both `ios/` and `pwa/` implement
features defined here. Platform-specific behaviour is noted per feature.

## Feature template

### Feature: [Name]
**Status:** planned | in-progress | shipped-ios | shipped-pwa | shipped-both
**API:** [endpoint(s) used]

#### Behaviour (both platforms)
-

#### iOS-specific
-

#### PWA-specific
-

---

## Features

### Feature: Incident List
**Status:** shipped-ios
**API:** `POST /api/incident_api.php` (method=getincidents)

#### Behaviour (both platforms)
- Display open incidents
- Swipe gestures for acknowledge / unacknowledge
- Pull-to-refresh and 120-second auto-refresh
- Navigate to incident detail on tap
- Badge with alarm state counts from `getincidentdetail` (`primary_alarm_log` + `relatedalarms`)

#### iOS-specific
- SwiftUI `List` with native swipe actions (right = ACK, left = UnACK)
- Auto-refresh countdown ring in the toolbar (`AutoRefreshButton`)

#### PWA-specific
- Not yet implemented
```

- [ ] **Step 7.3: Write `shared/push-payload-spec.md`**

Use the Write tool to create `/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/shared/push-payload-spec.md` with this exact content:

```markdown
# Push Payload Specification

Defines every notification payload type produced by `middleware/` and
consumed by `ios/` and `pwa/`. This is the contract between producer and
consumers — if you add a new payload type, update this file first.

## Payload template

### Type: [name]
**Trigger:** [what causes this notification]

```json
{
  "type": "[name]",
  "incident_id": "string",
  "severity": "critical | high | medium | low",
  "title": "string",
  "body": "string"
}
```

**iOS deep link:** `benem://[path]`
**PWA deep link:** `/[path]`

---

## Payload types

### Type: incident_opened
**Trigger:** New incident created in BHNM. Current APNs payload format in production.

```json
{
  "aps": {
    "alert": { "title": "string", "body": "string" },
    "sound": "default"
  },
  "incident_id": "<id>"
}
```

**iOS deep link:** tapping the notification posts `Notification.Name.pushNotificationIncidentTapped` via `NotificationCenter` with the `incident_id` in `userInfo`. `ContentView` switches to the Incidents tab and navigates to `IncidentDetailView`.

**PWA deep link:** `/incident/{incident_id}` (not yet implemented)

**Cold launch (iOS):** `AppDelegate.shared.pendingIncidentID` is read in `ContentView.onAppear`.
```

- [ ] **Step 7.4: Write `shared/api-spec.md`**

Use the Write tool to create `/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/shared/api-spec.md` with this exact content:

```markdown
# BHNM API Specification (BeNeM-consumed subset)

This is the narrower "which endpoints does BeNeM actually use" layer on top
of the full BHNM reference. For the full API surface, see
`BHNM_API_REFERENCE.md` in this directory.

## Base URLs

- Legacy API: `https://<BHNM_HOST>/fw/index.php?r=restful/`
- Open 3.0 API: `https://<BHNM_HOST>/api/`

## Authentication

- `password` — API key (stored in `NetreoAPIConfiguration.apiKey` on iOS)
- `pin` — Optional PIN (stored in `NetreoAPIConfiguration.pin` on iOS)

## Endpoints used by BeNeM

| Endpoint | Method | Consumer | Notes |
|---|---|---|---|
| | | | |

_Populate this table as features land. See `ios/CLAUDE.md` for the full current endpoint list used by the iOS app._
```

- [ ] **Step 7.5: Stage and verify**

```bash
git add shared/DECISION.md shared/feature-spec.md shared/push-payload-spec.md shared/api-spec.md
git status --short
ls -1 shared/
```

Expected: four new files staged, `ls shared/` shows all the expected files (DECISION.md, feature-spec.md, push-payload-spec.md, api-spec.md, plus the previously-moved BHNM_API_REFERENCE.md, PRD-BeNeM-Product-Requirements-Document.md, architecture.svg, credentials-and-keys-overview.md, bhnm-timeseries-metrics-api.md).

- [ ] **Step 7.6: Commit**

```bash
git commit -m "docs: add shared/ specification stubs

Add DECISION.md (verbatim April 2026 platform strategy record),
feature-spec.md (template + Incident List example), push-payload-spec.md
(template + incident_opened example matching current APNs payload), and
api-spec.md (narrow BeNeM-consumed subset, pointing at the full
BHNM_API_REFERENCE.md for details)."
```

---

## Task 8: Extend root `.gitignore` (commit 8 of 9) — Gate B

**Purpose:** Remove two obsolete rules (`test.json`, `docs/internal/`) and append monorepo subproject ignore blocks. After commit: run Gate B (middleware smoke test from the new path) before pushing.

**Files:**
- Modify: `.gitignore`

- [ ] **Step 8.1: Remove obsolete rules**

Use the Edit tool to remove these two blocks from `.gitignore`:

- `old_string`:
```
# Test / scratch files
test.json

# Internal / non-public docs (local only)
docs/internal/

```
- `new_string`: (empty string — removes the block entirely)

- [ ] **Step 8.2: Append monorepo subproject blocks**

Use the Edit tool to append the following to the end of `.gitignore`. Since Edit requires a unique `old_string`, use the last line of the current file as the anchor:

- `old_string`:
```
# Claude Code
.claude/
.superpowers/
```
- `new_string`:
```
# Claude Code
.claude/
.superpowers/

# --- Monorepo subproject ignores ---

# Xcode (scoped to ios/)
ios/**/*.xcuserstate
ios/**/xcuserdata/
ios/DerivedData/
ios/.build/

# Python / FastAPI middleware
middleware/__pycache__/
middleware/**/__pycache__/
middleware/*.pyc
middleware/.env
middleware/venv/
middleware/.venv/

# Node / PWA (future)
pwa/node_modules/
pwa/dist/
pwa/.env

# Secrets — never commit (repo-wide)
*.p8
*.pem
vapid_private_key*
```

- [ ] **Step 8.3: Verify and commit**

```bash
git diff .gitignore
git add .gitignore
git commit -m "chore: extend root .gitignore for monorepo subprojects

Remove two obsolete rules (test.json deleted in commit 3;
docs/internal/ moved to shared/ in commit 3). Append ignore blocks
for iOS Xcode artifacts, Python/FastAPI middleware artifacts, Node/PWA
artifacts, and repo-wide secret patterns (*.p8, *.pem, vapid_private_key*)."
```

- [ ] **Step 8.4: GATE B — middleware smoke test from new path**

```bash
cd middleware
cat README.md 2>/dev/null | head -30  # see if there are install/run instructions
```

Follow the middleware's README to start it locally. Typical workflow (adjust to what the README actually specifies):

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/middleware"
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt   # or whatever the README specifies
# Ensure .env is present at middleware/.env (with WEBHOOK_SECRET, APNs key path, VAPID keys)
uvicorn main:app --reload --port 8889
```

Expected: the middleware starts without errors and listens on port 8889.

From a second terminal, send a test webhook. If the middleware's own test fixtures exist (e.g. `middleware/tests/` or a sample curl in `middleware/README.md`), use those. As a minimum end-to-end check:

```bash
curl -X POST 'http://localhost:8889/webhook?secret=<WEBHOOK_SECRET>' \
  -H 'Content-Type: application/json' \
  -d '{
    "incident_id": "smoketest-001",
    "hostname": "smoketest-host",
    "host_state": "DOWN",
    "notification_type": "PROBLEM",
    "site": "Home",
    "service_desc": "Host Availability Check",
    "output": "PING CRITICAL - Packet loss = 100%"
  }'
```

Expected:
- Middleware logs show the webhook was received and a push was dispatched.
- A test push notification arrives on a test device (if a device is registered).

Stop the middleware (`Ctrl+C`), `deactivate` the venv.

**If Gate B fails** (middleware won't start, or webhook→push path is broken):
1. Determine whether the failure is **configuration** (e.g. `.env` missing, APNs key path wrong) or **code/path** (e.g. hardcoded absolute path in middleware source that was valid at the old location but not here).
2. Configuration failures are out of scope for this plan — fix `.env` or key paths and re-run Gate B. No commit needed.
3. Code/path failures are in scope: add a follow-up commit fixing the hardcoded paths, then re-run Gate B. This becomes commit 8a (unnumbered in the 9-commit plan).
4. Only push to origin (Task 9) after Gate B passes.

---

## Task 9: Push to `origin/main` (commit 9 is implicit — this is just the push)

**Purpose:** Publish the restructure. Until this step, everything has been local.

- [ ] **Step 9.1: Verify final local state**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
git log --oneline origin/main..HEAD
git status
ls -1
```

Expected:
- `git log origin/main..HEAD` shows 8 or 9 commits (depending on whether Step 5.5 produced an extra cleanup commit) plus any follow-ups from Gate B, including the merge commit from the middleware import.
- `git status` is clean.
- `ls` shows: `CLAUDE.md`, `LICENSE`, `README.md`, `.gitignore`, `.claude/`, `.superpowers/`, `.firecrawl/`, `docs/`, `ios/`, `middleware/`, `pwa/`, `shared/`, and nothing else of note at root.

- [ ] **Step 9.2: Push main and the safety tag**

```bash
git push origin main
git push origin pre-monorepo-restructure
```

Expected: push succeeds. GitHub web UI at `github.com/ThomasStolt/BeNeM` now shows the four subdirectories.

- [ ] **Step 9.3: Verify on GitHub**

Open `https://github.com/ThomasStolt/BeNeM` in a browser. Confirm:
- Top-level shows `ios/`, `middleware/`, `pwa/`, `shared/`, `docs/`, plus `CLAUDE.md`, `README.md`, `LICENSE`, `.gitignore`
- Clicking `middleware/` shows the imported bhnm-apns tree
- Clicking on a middleware source file (e.g., `middleware/main.py`) and viewing its history shows the original bhnm-apns commit history, not just the import merge

- [ ] **Step 9.4: Resume OneDrive sync**

Ask the user to resume OneDrive sync (menu bar → Resume syncing). A large batch of renames will propagate to OneDrive — this is expected and safe.

- [ ] **Step 9.5: Post-restructure cleanup (manual, by user, not in this plan)**

Inform the user that the following cleanup steps are theirs to perform when they are confident in the new layout:

1. Delete the local `~/OneDrive/Documents/Github/bhnm-apns` clone (history is now fully preserved inside the monorepo).
2. Archive or delete the `ThomasStolt/bhnm-apns` repository on GitHub (web UI: Settings → Danger Zone).
3. Rewrite `README.md` for the monorepo (currently still the iOS-only README — tracked as a follow-up in the spec §11).
4. Delete `M1BJKI1M3C52.png` from the repo root if desired (it is a stray untracked 512×512 PNG, gitignored, no git action needed).

---

## Follow-ups (tracked in the spec, not executed by this plan)

- Rewrite `README.md` for the monorepo post-restructure.
- Revisit Gate A: consider upgrading from `xcodebuild -list` to a full `xcodebuild build` after first execution experience.
- Populate `shared/feature-spec.md`, `push-payload-spec.md`, `api-spec.md` organically as cross-cutting features land.
- Delete `ThomasStolt/bhnm-apns` GitHub repo and local clone after the user is confident in the new layout (Task 9, Step 9.5).

---

## Full commit log at end of execution (expected)

```
<sha> chore: extend root .gitignore for monorepo subprojects
<sha> docs: add shared/ specification stubs
<sha> docs: replace middleware/CLAUDE.md and add pwa/CLAUDE.md
[optional] chore: remove imported middleware/.superpowers (tool cache, not source)
[optional] chore: remove middleware/.gitkeep placeholder (superseded by import)
<sha> chore: import bhnm-apns middleware history into middleware/  [merge commit]
<sha> chore: split CLAUDE.md into monorepo root and ios/
<sha> chore: move shared docs and API reference into shared/
<sha> chore: move iOS sources and tooling into ios/
<sha> chore: create monorepo subdirectories
<sha> docs: correct spec for gitignored source files  [pre-existing]
<sha> docs: add monorepo restructure design spec  [pre-existing]
<sha> docs: update user guide with device header chart and CPU cores info  [pre-existing]
```

Plus, reachable via the merge commit, the full bhnm-apns commit history (now with every path prefixed by `middleware/`).
