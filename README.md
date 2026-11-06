# Spacelift Stacks

An unofficial macOS app for browsing Spacelift stacks. It is read-only unless you turn on actions in Settings (see below). It shells out to `spacectl`, so it uses
your existing `spacectl` login and shows only what your account can see.

Tabs: Overview (includes the latest run), Run history (runs on top, the selected run's changes below), Logs, Live logs, Outputs, Environment, Everything.
Secret values are never shown (Spacelift masks them).

The full [user manual](MANUAL.md) describes every feature and when it is available.

## Requirements

- macOS 14 (Sonoma) or newer, Apple Silicon or Intel
- [`spacectl`](https://github.com/spacelift-io/spacectl) installed and logged in

```bash
brew install spacelift-io/spacelift/spacectl
spacectl profile login <your-spacelift-subdomain>
spacectl stack list --limit 1     # should print a stack, not an auth error
```

The app looks for `spacectl` in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` and `~/go/bin`.

## Install

1. Download the zip from the [Releases](../../releases) page (check it against `SHA256SUMS`), unzip, and drag `spacectl-ui.app` to `/Applications`.
2. The app is not notarized (ad-hoc signed), so macOS blocks the first launch. Clear the
   quarantine flag once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/spacectl-ui.app
   ```

   Alternatively: try to open it, then System Settings > Privacy & Security > "Open Anyway".
3. Open it and type at least 2 characters in the search box.

## Usage notes

- Search is server-side and needs 2+ characters, because listing every stack takes minutes.
- Run history lists tracked, proposed and drift-detection runs (Type column, filter on top). Overview and the default run for Logs and changes use the latest tracked run.
- Run history: select a row to see that run's changes below it and to choose the run Logs and Live logs show. Double-click jumps to its logs. Right-click offers Details, Open logs and Follow live (only for runs in progress); Cmd+I or the info button at the start of a row shows that run's details.
- Logs show each phase (Queued, Preparing, Planning, Applying, Finished…) as a colored heading with extra spacing.
- Live logs follows a run with `spacectl --tail`; there is no push API, so it is a stream, not polling.
- The sidebar has two modes: **Search**, and **Recent** for the last 30 stacks you opened (kept locally as stack IDs only). Right-click a recent to remove it, or use "Clear history".
- The × button in the stack header, or Esc, closes the open stack (and stops a live log stream).
- Cmd+K opens the command palette: type to search stacks on the server, jump to a tab, or refresh. Arrow keys and Return to pick, Esc to close.
- Refresh with Cmd+R.

## Actions (off by default)

Turn on **Settings (Cmd+,) > Enable actions** to get these. They run `spacectl` as you, so they use your Spacelift permissions, and every one asks for confirmation.

- **Trigger** (stack header): starts the first run of a stack that has never had a tracked run (`spacectl stack deploy`, a tracked run at the branch head). It is greyed out once the stack has run before.
- **Retry failed run**: right-click a failed run in Run history (`spacectl stack retry`).
- **Trigger tab** (sidebar): search, tick stacks that have run before, and trigger them all. To confirm you type `deploy <count>` or `deploy <search>`. The sheet warns about stacks with **autodeploy** (a new run applies immediately) and stacks already blocked by another run. At most 3 runs are in progress at once: the next stack starts when one settles (finished, failed, discarded, or waiting for a person to confirm). Stop ends the waiting; runs already created keep going in Spacelift.

Runs are never confirmed or force-applied from the app.

## Build from source

Needs the Swift toolchain (Xcode or Command Line Tools), no Xcode project.

```bash
./build.sh          # builds spacectl-ui.app (universal)
./build.sh dist     # also writes dist/spacectl-ui-<version>.zip
```

To release: bump `VERSION` in a PR and merge it. The Release workflow builds the zip and publishes it as the GitHub Release `v<VERSION>` (the tag is created with it).

## Contributing and license

Issues and pull requests are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under the [MIT License](LICENSE).

This project is not affiliated with or endorsed by Spacelift. "Spacelift" is a trademark of its owner.
