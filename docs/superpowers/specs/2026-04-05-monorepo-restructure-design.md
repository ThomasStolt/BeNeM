# Design: BeNeM Monorepo Restructure

**Date:** 2026-04-05
**Status:** Approved, awaiting implementation plan
**Source task:** `~/Downloads/TASK_monorepo_restructure.md`
**Source decision:** `~/Downloads/DECISION.md`

## 1. Context and Goals

The current `ThomasStolt/BeNeM` repository contains only the iOS Swift/SwiftUI app. The companion `ThomasStolt/bhnm-apns` repository contains the Python/FastAPI push-notification middleware. Per the April 2026 platform strategy decision (preserved verbatim in `shared/DECISION.md`), both are consolidated into a single monorepo that will also host a future Progressive Web App targeting Android.

**Goals:**

- Convert `ThomasStolt/BeNeM` into a monorepo with four top-level subprojects: `ios/`, `middleware/`, `pwa/`, `shared/`.
- Import the full git history of `bhnm-apns` under `middleware/` with per-file history preserved.
- Preserve the accumulated iOS context in the existing root `CLAUDE.md` by relocating it to `ios/CLAUDE.md` rather than discarding it.
- Produce an auditable, bisectable commit sequence with a verification gate before the irreversible middleware-history import and before the remote push.
- Leave the original `bhnm-apns` GitHub repository untouched so it remains a fallback until manual deletion by the user.

**Non-goals:**

- Scaffolding PWA code beyond creating `pwa/src/` and `pwa/CLAUDE.md`.
- Modifying Xcode build settings, signing, or TestFlight configuration.
- Deleting the `bhnm-apns` GitHub repository (manual step for the user after verification).
- Rewriting `README.md` for the monorepo (tracked as follow-up).
- Populating `shared/feature-spec.md`, `push-payload-spec.md`, or `api-spec.md` with comprehensive content — stubs only; spec-first going forward.

## 2. Verified Facts (Step 0)

| Fact | Value |
|---|---|
| BeNeM local path (canonical) | `/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM` (the `~/OneDrive/...` path is a symlink to this) |
| bhnm-apns local path | `~/OneDrive/Documents/Github/bhnm-apns/` |
| GitHub username | `ThomasStolt` |
| iOS GitHub repo name | `BeNeM` |
| Middleware GitHub repo name | `bhnm-apns` |
| Default branch (both) | `main` |
| OneDrive sync status during execution | **Paused by user** before execution begins |

## 3. Target Structure

```
BeNeM/                          (monorepo root on ThomasStolt/BeNeM)
├── CLAUDE.md                   (new — thin monorepo overview)
├── README.md                   (unchanged for now; follow-up to rewrite)
├── LICENSE                     (unchanged)
├── .gitignore                  (extended — see §9)
├── .claude/                    (unchanged — tooling config)
├── .superpowers/               (unchanged — tooling config)
├── .firecrawl/                 (unchanged — tooling config)
├── docs/
│   └── superpowers/            (unchanged — skill output dir for plans/specs)
│       ├── plans/
│       └── specs/
├── ios/
│   ├── CLAUDE.md               (inherits ~95 % of current root CLAUDE.md)
│   ├── BeNeM/                  (moved from root)
│   ├── BeNeM.xcodeproj         (moved from root)
│   ├── build_and_deploy.sh     (moved from root)
│   ├── build.local.sh(.example) (moved from root)
│   ├── generate_benem_link.py  (moved from root)
│   ├── .env.template           (moved from root)
│   ├── scripts/                (moved from root)
│   ├── images/                 (moved from root)
│   ├── SETUP.md                (moved from root)
│   ├── CHANGELOG.md            (moved from root)
│   └── docs/
│       └── user-guide.html     (moved from docs/)
├── middleware/
│   ├── CLAUDE.md               (new, absorbs push architecture content)
│   └── (full bhnm-apns tree, imported with history — see §6)
├── pwa/
│   ├── CLAUDE.md               (new, placeholder)
│   └── src/                    (empty, .gitkeep only)
└── shared/
    ├── DECISION.md             (verbatim from ~/Downloads/DECISION.md)
    ├── BHNM_API_REFERENCE.md   (moved from root)
    ├── PRD-BeNeM-Product-Requirements-Document.md (moved from docs/)
    ├── architecture.svg        (moved from docs/)
    ├── credentials-and-keys-overview.md (moved from docs/)
    ├── bhnm-timeseries-metrics-api.md (moved from docs/internal/)
    ├── feature-spec.md         (new, stub + one worked example)
    ├── push-payload-spec.md    (new, stub + incident_opened example)
    ├── api-spec.md             (new, stub pointing to BHNM_API_REFERENCE.md)
    └── examples/
        └── webhook-test.sh     (was test.json at root)
```

## 4. File Movement Plan

The recipe's single `for item in $(ls -A | grep -vE ...)` loop is replaced with an explicit, auditable list of `git mv` commands grouped by destination. This encodes the split decisions, handles whitespace safely, and fails loudly on typos.

### 4.1 Files moving to `ios/`

| Source | Destination |
|---|---|
| `BeNeM/` | `ios/BeNeM/` |
| `BeNeM.xcodeproj` | `ios/BeNeM.xcodeproj` |
| `build_and_deploy.sh` | `ios/build_and_deploy.sh` |
| `build.local.sh` | `ios/build.local.sh` |
| `build.local.sh.example` | `ios/build.local.sh.example` |
| `generate_benem_link.py` | `ios/generate_benem_link.py` |
| `.env.template` | `ios/.env.template` |
| `scripts/` | `ios/scripts/` |
| `images/` | `ios/images/` |
| `SETUP.md` | `ios/SETUP.md` |
| `CHANGELOG.md` | `ios/CHANGELOG.md` |
| `docs/user-guide.html` | `ios/docs/user-guide.html` |

### 4.2 Files moving to `shared/`

| Source | Destination |
|---|---|
| `BHNM_API_REFERENCE.md` | `shared/BHNM_API_REFERENCE.md` |
| `docs/PRD-BeNeM-Product-Requirements-Document.md` | `shared/PRD-BeNeM-Product-Requirements-Document.md` |
| `docs/architecture.svg` | `shared/architecture.svg` |
| `docs/credentials-and-keys-overview.md` | `shared/credentials-and-keys-overview.md` |
| `docs/internal/bhnm-timeseries-metrics-api.md` | `shared/bhnm-timeseries-metrics-api.md` |
| `test.json` | `shared/examples/webhook-test.sh` |

### 4.3 Files staying at repo root

`LICENSE`, `README.md`, `.gitignore`, `.claude/`, `.superpowers/`, `.firecrawl/`, `docs/superpowers/` (plans and specs subdirs), and the new monorepo `CLAUDE.md`.

### 4.4 Untracked / ignored files — no git action

- `.DS_Store` (not tracked, verified)
- `M1BJKI1M3C52.png` (not tracked; stray 512×512 PNG at root; user can delete manually)

## 5. CLAUDE.md Split

The existing root `CLAUDE.md` (~180 lines) contains hard-won accumulated context and **must not be discarded**. The recipe's thin `ios/CLAUDE.md` (~20 lines) and new root `CLAUDE.md` (~40 lines) are treated as a starting point that gets enriched from the existing content.

### 5.1 `ios/CLAUDE.md` — inherits from current root `CLAUDE.md`

**Method:** `git mv CLAUDE.md ios/CLAUDE.md`, then edit in place.

**Retitle:** `# BeNeM – Claude Code Context` → `# BeNeM iOS – Claude Code Context`

**Add** upward pointer paragraph near the top: *"Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules and `../shared/` for API contracts and feature specs."*

**Keep verbatim:** Naming note (BHNM vs Netreo), Project Structure, API section (all endpoints, time-series metrics body, ACK/UnACK body), Tactical Overview, Data Refresh, Versioning, Build & Deploy, Important Notes.

**Strip** (moves to `middleware/CLAUDE.md`): the producer-side middleware architecture and deployment details from the Push Notifications section — specifically the middleware repo pointer, deployment host, Docker/Caddy notes, `/register` and `/webhook` endpoint descriptions.

**Keep in `ios/CLAUDE.md`** (consumer side stays with iOS): `AppDelegate` APNs token registration, `UNUserNotificationCenterDelegate` handling, deep-link tap handler behaviour, cold-launch pending incident ID, `BeNeM.entitlements` `aps-environment = development`, APNs custom-data payload consumption.

**Audit** any filesystem-relative references during execution (most are already written relative to the repo root and will resolve from inside `ios/` naturally).

### 5.2 Root `CLAUDE.md` — new, ~60 lines

Structure:

1. One-paragraph intro (what BeNeM is, pulled from current CLAUDE.md opening)
2. Structure table: `ios/`, `middleware/`, `pwa/`, `shared/` with one-line descriptions
3. Naming note (BHNM vs Netreo, legacy type-name prefix) — cross-cutting
4. **Feature parity rule (softened from recipe):** *"Features are implemented on `ios/` first. As `pwa/` matures, features land on both unless marked platform-specific in `shared/feature-spec.md`. Always update `shared/feature-spec.md` before or alongside implementation."*
5. Push notification architecture diagram: `BHNM Incident → Webhook → bhnm-apns middleware → APNs / Web Push → device`, plus pointers to `middleware/` (producer), `ios/` and `pwa/` (consumers)
6. Sessions guidance: when to open Claude Code at root vs in a subdir (from recipe)
7. Minimum BHNM version constraint — cross-cutting

### 5.3 `middleware/CLAUDE.md` — new

Built from the recipe's template, enriched with content pulled from the current root `CLAUDE.md` Push Notifications section: middleware repo reference, deployment location (`bhnm-apns.hurrikap.org`, Linode, Caddy), authentication (`X-Webhook-Token` header, `?secret=` query param), APNs environment routing (sandbox vs production per device token), `/register` and `/webhook` endpoints, deep-link config generation flow.

### 5.4 `pwa/CLAUDE.md` — new

Exactly as the recipe shows. Placeholder context for future PWA work.

**Invariant:** every piece of information in the current root `CLAUDE.md` ends up somewhere in the split — `ios/`, root, or `middleware/`. No context is lost.

## 6. Middleware History Import (filter-repo)

This is the most irreversible step and gets its own section.

**Tool:** `git filter-repo` (not part of stock git). Install via `brew install git-filter-repo`.

**Rationale for this approach vs alternatives:**

| Option | Per-file `git log --follow` | Rewrites history | Chosen |
|---|---|---|---|
| `git read-tree --prefix` (recipe's original) | ❌ Stops at import commit | No | No |
| `git subtree add` | ⚠️ Partial, varies by tool | No | No |
| **`git filter-repo --to-subdirectory-filter`** | ✅ Full history walks back through filter-repo commits | Yes (only the rewritten clone) | **Yes** |

Per-file history is the deciding factor — middleware debugging over the next several years benefits far more from full `git log --follow` support than the restructure benefits from avoiding a history rewrite. The rewrite is contained to a temporary clone.

**Procedure:**

```bash
WORK=$(mktemp -d)
git clone ~/OneDrive/Documents/Github/bhnm-apns "$WORK/bhnm-apns"
cd "$WORK/bhnm-apns"
git filter-repo --to-subdirectory-filter middleware

cd <BENEM_LOCAL_PATH>
git remote add middleware-import "$WORK/bhnm-apns"
git fetch middleware-import
git merge --allow-unrelated-histories middleware-import/main \
  -m "chore: import bhnm-apns middleware history into middleware/"
git remote remove middleware-import
rm -rf "$WORK"
```

**Safety properties:**

- The user's real `bhnm-apns` clone is never modified (filter-repo operates on a temp clone).
- Commit SHAs for imported commits change (inherent to any rewrite), but authors, dates, messages, and parent chain are preserved.
- The `ThomasStolt/bhnm-apns` GitHub repo is untouched by this procedure and remains a fallback until manual deletion.
- Failure at any point: reset to `pre-monorepo-restructure` tag, fix root cause, re-run.

**Failure responses:**

| Failure | Response |
|---|---|
| `git filter-repo` not installed | `brew install git-filter-repo`, re-run |
| Merge conflict (unexpected — disjoint paths) | Investigate. Do not force. |
| `git log --follow middleware/main.py` shows no history | Reset to safety tag, re-run filter-repo step with logging |
| Middleware doesn't start from new location | Not a history issue; follow-up commit to fix any hardcoded paths in middleware source |

## 7. Execution Order and Commit Granularity

Eight logical commits plus a safety tag. **Nothing is pushed to `origin/main` until all commits land locally and both verification gates pass.**

### 7.1 Safety net (pre-work)

```bash
git tag pre-monorepo-restructure
git branch backup/pre-monorepo
```

### 7.2 Commits

| # | Message | Contents | Gate |
|---|---|---|---|
| 1 | `chore: create monorepo subdirectories` | `mkdir ios middleware pwa/src shared shared/examples ios/docs`; add `.gitkeep` files where needed | Dirs exist |
| 2 | `chore: move iOS sources and tooling into ios/` | Explicit `git mv` list per §4.1 | Diff review |
| 3 | `chore: move shared docs and API reference into shared/` | Explicit `git mv` list per §4.2 | Diff review |
| 4 | `chore: split CLAUDE.md into monorepo root and ios/` | `git mv CLAUDE.md ios/CLAUDE.md`, edit per §5.1, write new root `CLAUDE.md` per §5.2 | **Gate A:** `xcodebuild -list -project ios/BeNeM.xcodeproj` succeeds |
| 5 | `chore: import bhnm-apns middleware history into middleware/` | Procedure per §6 | `ls middleware/main.py` and `git log --follow middleware/main.py` show full history |
| 6 | `docs: add middleware/ and pwa/ CLAUDE.md files` | New files per §5.3, §5.4 | Files exist |
| 7 | `docs: add shared/ specification stubs` | `DECISION.md` verbatim + `feature-spec.md`, `push-payload-spec.md`, `api-spec.md` (§8) | Files exist |
| 8 | `chore: extend root .gitignore for monorepo subprojects` | Append blocks from §9 to existing `.gitignore` | **Gate B:** middleware starts from `middleware/` and delivers a test push via `shared/examples/webhook-test.sh` |

**Gate A** (between commits 4 and 5): confirm the Xcode project still resolves from its new location before taking the irreversible history-import step. `xcodebuild -list` is the minimum viable check — it parses `project.pbxproj` and will surface broken relative paths. A full build is stronger but costs minutes; not justified at this gate. *(Follow-up: revisit whether to upgrade Gate A to a full `xcodebuild build`.)*

**Gate B** (after commit 8, before push): end-to-end middleware smoke test from the new path. This catches hardcoded-path regressions in the middleware itself before we make the restructure visible on GitHub.

### 7.3 Push

Only after both gates pass:

```bash
git push origin main
git push origin --tags  # publish the safety tag
```

### 7.4 Rollback

```bash
git reset --hard pre-monorepo-restructure
# or
git checkout backup/pre-monorepo
```

Remote is untouched until the explicit push step, so rollback is purely local.

## 8. `shared/` Stub Contents

Deliberately minimal. The principle is **spec-first going forward**, not reverse-engineering existing code into specs retroactively.

1. **`shared/DECISION.md`** — verbatim copy of `~/Downloads/DECISION.md`. No edits.
2. **`shared/feature-spec.md`** — the recipe's template plus one seeded entry: "Incident List", marked `shipped-ios`, to demonstrate the pattern.
3. **`shared/push-payload-spec.md`** — the recipe's template plus one seeded entry: "Type: `incident_opened`" using the current APNs payload from root `CLAUDE.md` (`{"aps": {...}, "incident_id": "<id>"}`).
4. **`shared/api-spec.md`** — the recipe's template with a pointer to `shared/BHNM_API_REFERENCE.md` and an empty endpoint table for future population.

## 9. Root `.gitignore` Extension

Append the following blocks to the existing `.gitignore`. Existing rules are not modified or deduplicated.

```gitignore
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

## 10. Risks and Open Items

1. **README.md not updated.** The post-restructure README is still the iOS README. **Follow-up task:** rewrite README.md for the monorepo (new top-level intro, link to each subproject, platform strategy summary).
2. **`build.local.sh` tracked state.** Not verified at design time. If tracked, moving it carries the committed device UDID into `ios/build.local.sh`. Expected, noted for visibility.
3. **Gate A is `xcodebuild -list` only.** **Follow-up item:** revisit whether Gate A should be upgraded to a full `xcodebuild build` after first execution experience.
4. **PWA subdir is empty.** Feature-parity rule in root `CLAUDE.md` is softened to match reality.
5. **OneDrive resume after completion.** User resumes sync after commit 8; large rename batch is expected and safe.
6. **Prerequisite:** `git filter-repo` must be installed (`brew install git-filter-repo`) before commit 5.

## 11. Follow-ups (tracked, not in this spec)

- [ ] Rewrite `README.md` for the monorepo after restructure ships.
- [ ] Revisit Gate A: consider upgrading from `xcodebuild -list` to a full `xcodebuild build`.
- [ ] Populate `shared/feature-spec.md`, `push-payload-spec.md`, `api-spec.md` organically as cross-cutting features land.
- [ ] Manually delete `ThomasStolt/bhnm-apns` GitHub repo and local clone after Gate B passes and the user has confidence in the new layout (recipe's Step 8).
