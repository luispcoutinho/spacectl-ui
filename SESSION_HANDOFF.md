# Session handoff: spacectl-ui

Written 2026-11-07. Repo: `~/Desktop/git/personal/spacectl-ui` (remote `luispcoutinho/spacectl-ui` on GitHub). This file is untracked and uncommitted: do not commit it unless the user asks.

## 1. Goal

Build and ship **spacectl-ui** ("Spacelift Stacks" in the UI): a macOS SwiftUI app that shells out to `spacectl` to browse Spacelift stacks, with optional, opt-in actions (trigger, retry, preview). It started as a shell-script helper, became an app shared with a team, then a personal MIT open-source repo ("anyone can contribute"). Constraints: distribute by zip / future Homebrew (no App Store), builds run on GitHub Actions, no Apple Developer account (ad-hoc signed), actions must stay safe by default.

## 2. Current state

- Repo `~/Desktop/git/personal/spacectl-ui`: branch `main` = `origin/main` = `df781d7`, tag `v0.4.1`. `git status` clean, no uncommitted changes. Local-only ignored artifacts: `.build/`, `spacectl-ui.app/`, `dist/`.
- PRs #1 (0.3.0), #2 (0.4.0), #3 (0.4.1) are merged. GitHub Releases v0.2.0 to v0.4.1 exist (v0.4.1 is Latest).
- **Verified (run in this session):**
  - `./build.sh` builds a universal (arm64 + x86_64) app with a valid ad-hoc signature, and it launches.
  - CI (`ci.yml`) passed on GitHub's `macos-15` runner; the release workflow's manual dry run passed (build, checksum, artifact upload). The auto-release on `VERSION` change is evidenced by the releases list; I did not read those run logs.
  - Against a real Spacelift account (read-only calls): tracked and preview run merging, run filters, never-run stacks returning JSON `null`, stack `state` of `NONE`, `canWrite` and `Blocker` decoding.
  - The user reported testing the 0.4.1 feature successfully; what exactly they covered (Preview only, Deploy, batch) was not stated.
- **Unverified by me:** Deploy, Retry and the batch runner against real runs (I never created a run); reading the new run's ID from `spacectl` output (a ULID regex, then a newest-run fallback); the 3-in-flight throttle and Stop; the UI by hand (no UI automation was available; only early screenshots); build-provenance attestation (skipped on private repos, never run).
- Nothing half-finished in code. 0.5.0 is planned, not started.

## 3. Decisions and rationale

- **SwiftPM, no Xcode project;** built with Command Line Tools. UI state lives in the `@Observable @MainActor` `StacksViewModel`, because the `@State` macro plugin ships with Xcode only. Persistence uses `UserDefaults` directly (no `@AppStorage`).
- **Universal binary:** build each arch separately (`--triple <arch>-apple-macosx14.0`), copy each binary out, then `lipo`. Building both into the shared output dir without copying failed with `lipo: same architectures (x86_64) found`.
- **Signing:** ad-hoc only. A downloaded zip gets the quarantine flag and Gatekeeper blocks it; locally built apps never get it. Documented fix: `xattr -dr com.apple.quarantine`. Developer ID + notarization (paid account) and a Homebrew tap/cask were discussed and deferred.
- **Releases:** merging a change to `VERSION` on `main` triggers `release.yml`, which builds the zip and runs `gh release create v<VERSION> --target <sha>`. Chosen over tag-triggered and release-please for simplicity (one maintainer). Actions are pinned to commit SHAs. The attestation step runs only when the repo is public.
- **Naming:** binary/target `spacectl-ui` (was `SpaceliftGUI`); display name "Spacelift Stacks"; bundle ID `io.github.luispcoutinho.spacectl-ui` (also the `defaults` domain). MIT license; README says unofficial.
- **Run history bug:** `spacectl stack run list` omits proposed and drift runs unless `--preview-runs`; the two lists are disjoint, so the app fetches both in parallel. "Latest run" means the **newest tracked run** (user's choice over newest-of-any).
- **Actions are opt-in** (Settings > Enable actions, default off). "Trigger" = `spacectl stack deploy` (there is no `trigger` command; it matches the web UI's Trigger). Header Trigger is enabled only when the stack has no tracked run; the Trigger sidebar tab handles stacks that have run. Never pass `--auto-confirm` or `--force-apply`.
- **Batch throttle:** "3 at a time" means 3 runs in progress, not 3 requests, because `deploy`/`preview` return once the run exists. The batch waits for each run to settle (Finished, Failed, Discarded, Canceled, Stopped, Skipped, Unconfirmed, Pending review) polling every 10 s.
- **0.4.1:** Trigger tab got a Preview | Deploy switch. Preview (default) lists every match, confirms with a plain sheet; Deploy lists only stacks that have run, warns on autodeploy/blockers and needs a typed `deploy <count>` or `deploy <search>`.
- **Rejected or changed:** details popover anchored to a header button (looked disconnected) or a last-column button (opened at the window edge), now the first column; per-run "Deploy again"; per-run "Preview again" (dropped; Preview lives only in the Trigger tab); "every match" implemented as a Select-all button, not an unreviewed bulk run.
- **Not implemented (deferred to 0.5.0 by the user):** Promote, Confirm, Discard, Replan. Cancel, Stop and Approve are not planned.

## 4. Files touched

All under the repo. Central: `Sources/spacectl-ui/Spacectl.swift` (spacectl wrapper, run merging, `deploy`/`preview`/`retry`, null-safe list decoding), `Trigger.swift` (actions, batch runner, throttle), `TriggerViews.swift` (Trigger tab, confirm sheet, Settings, no-runs view), `Views.swift` (sidebar, header, tabs, Run history), `ViewModel.swift` (state, loading, cache), `Models.swift` (`Run`, `RunKind`, `RunFilter`, `Stack`), `build.sh`, `.github/workflows/ci.yml` and `release.yml`, `MANUAL.md`, `README.md`, `VERSION`.
Incidental: `LogStreamer.swift` (colored phase headings), `CommandPalette.swift`, `Recents.swift`, `Theme.swift`, `SpacectlUIApp.swift`, `Package.swift`, `CONTRIBUTING.md`, `LICENSE`, `.gitignore`, `make-icon.swift`, `Resources/AppIcon.png`, `.github/pull_request_template.md`.

## 5. Key context

- **Build:** `./build.sh` (app) or `./build.sh dist` (adds `dist/spacectl-ui-<version>.zip`); `swift build` for a quick compile. No tests and no linter are configured.
- **spacectl commands used:** `stack list --search --limit`, `stack show`, `stack run list [--preview-runs]`, `stack changes --run`, `stack logs --run [--phase|--tail]`, `stack outputs`, `stack environment list`, `stack deploy`, `stack preview`, `stack retry --run`.
- **Gotchas:** empty lists print JSON `null`, not `[]`; `stack show` prints `Blocker: {}` when nothing blocks; a stack that never ran has state `NONE`; run list fetches 10 per kind and search 200 stacks; GUI apps lack the shell PATH, so `spacectl` is probed in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/go/bin`; logs use `NO_COLOR=1` and ANSI is stripped; phase banners are three lines (dashes, `PHASE<TAB>date`, dashes) parsed by a small state machine in `LogTextView.Coordinator`.
- **Environment tool limits (assistant side):** `git push` and `gh workflow run` were denied by the tool-permission layer, so the user ran them. Read-only `gh` calls work.
- **Instructions that shaped the work:** organization rules: no real secrets or customer data in code or docs; flag drafts meant for customers/the public for review; do not present content as official company statements. User rules: ask before pushing or creating PRs; match surrounding code style and comment density; conventional commits; use they/them when pronouns are unknown. Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR bodies end with the "Generated with Claude Code" line.

## 6. Open issues

- **Unconfirmed clearance before going public:** the app was built in a work checkout. The user has not confirmed an employer IP/open-source check, nor the right to license the icon. Repo visibility was private as of 2026-11-05 and was not rechecked. Do not change visibility without the user's go-ahead.
- Deploy, Retry and the batch (throttle, Stop, ID parsing) need a real-run test on a sandbox stack. The batch shows a red row "A run was started but its ID could not be read..." if parsing fails.
- Manual claim not verified: Live logs "should" replay a finished run.
- Cosmetic, uninvestigated: sidebar selection is system blue; the Overview Description field shows odd capitalization (probably upstream data).

## 7. Next steps

1. **(Recommended start)** Ask the user what their 0.4.1 test covered, then branch `feature/run-actions` from `main` for **0.5.0**: Promote, Confirm, Discard, Replan. Behind "Enable actions", each with its own confirmation alert, as **per-run right-click items only, no bulk**. Confirm is effectively an apply, so word its dialog accordingly.
2. Check flags with `spacectl stack <promote|confirm|discard|replan> --help`. Replan, confirm and discard apply only to Unconfirmed tracked runs; promote to a finished proposed run. Gate the menu items on `Run.state` and `Run.kind`. Add `PendingAction` cases and `Spacectl` wrappers beside `retry` in `Spacectl.swift` and `Trigger.swift`; add menu items in `HistorySection` (`Views.swift`).
3. Update `MANUAL.md` (capability table, run-history menu table, recipes), `README.md`, and bump `VERSION` to `0.5.0`.
4. Build, launch, test on a sandbox stack, commit with a conventional message, give the user the push command and a PR title/description. Merging publishes `v0.5.0`.
5. Later, if asked: Homebrew tap/cask, Developer ID notarization, making the repo public (after the clearance above).

## 8. User preferences observed

- Wants a **review before implementation** ("review before advancing", "review these") with a recommendation, then a short "yes" or a numbered answer set; decides each question explicitly.
- Prefers concise, direct answers and honest reporting of what was not tested.
- Works through PRs and merges them personally; wants PR title/description text and the exact push command, one version bump per PR, and does the pushing.
- Cares about safety: opt-in writes, confirmations, typed phrases, no auto-confirm.
- Wants naming consistent with the Spacelift web UI ("Trigger"), minimal UI clutter, and scope kept tight (explicitly deferred features to 0.5.0). Corrected the popover placement twice and rejected per-run Deploy.

## Redactions

- Real Spacelift stack IDs from the work account (internal resource names): omitted.
- Personal email from git config and the local home-directory username: omitted (paths shortened to `~`).
- No tokens, keys or Spacelift subdomain appeared in the session.
