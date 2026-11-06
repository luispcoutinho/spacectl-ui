# Spacelift Stacks: user manual

This manual describes every feature of the app and the conditions under which it is available. For installation and build instructions, see the [README](README.md).

The app is a front end for `spacectl`. It runs `spacectl` commands as you, so it shows only what your Spacelift account can see, and every action uses your own permissions.

## Contents

1. [Before you start](#before-you-start)
2. [The window](#the-window)
3. [Finding stacks](#finding-stacks)
4. [Command palette](#command-palette)
5. [Stack header](#stack-header)
6. [Tabs](#tabs)
7. [Actions (off by default)](#actions-off-by-default)
8. [Keyboard shortcuts](#keyboard-shortcuts)
9. [Stored data and reset](#stored-data-and-reset)
10. [Troubleshooting](#troubleshooting)

## Before you start

- macOS 14 (Sonoma) or newer, Apple Silicon or Intel.
- [`spacectl`](https://github.com/spacelift-io/spacectl) installed and logged in (`spacectl profile login <your-spacelift-subdomain>`). The app looks for it in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` and `~/go/bin`. If it is missing, the sidebar says so.
- The app is not notarized. On the first launch of a downloaded copy, clear the quarantine flag once (see the README).
- Secret values are never shown. Spacelift masks them, and the app shows `*****` or `<computed>` instead.

## The window

- **Left pane:** finding stacks. It has a **Search | Recent** switch, plus a **Trigger** segment when actions are enabled.
- **Right pane:** the open stack, with a header and a row of tabs. With no stack open it shows "Select a stack".

## Finding stacks

### Search

- Type at least **2 characters**. Search runs on the server, because listing every stack takes minutes.
- Results are limited to **200**. Narrow the search if you hit the limit.
- Each result shows the stack ID, a state dot and pill color, its state and the author of the tracked commit.
- Click a result to open it.

### Recent

- Lists the last **30** stacks you opened, newest first, without duplicates ("Opened 2 hours ago").
- Only stack IDs are stored, never states, so nothing shown there is stale. Opening a stack loads its live state.
- Right-click an entry to **Remove from history**, or use **Clear history** in the footer.
- If a recent stack was deleted, opening it shows the error `spacectl` returns.

## Command palette

Press **⌘K** (or the ⌘K button in the sidebar footer).

- With an empty box it lists your recent stacks.
- Typing filters tab names and the Refresh action (only while a stack is open). Typing 2 or more characters also searches stacks on the server, after a short pause.
- **↑ ↓** to move, **↵** to open, **Esc** to close.
- It opens stacks and jumps to tabs. It does not run Trigger or Retry.

## Stack header

Shows the stack ID, `repository · branch`, and the state pill. Buttons on the right:

| Button | What it does | Availability |
|---|---|---|
| **Trigger** | Starts the stack's first run | Only with actions enabled; see [Trigger button](#trigger-button-first-run) |
| **Refresh** (⌘R) | Reloads everything for the open stack | Always |
| **×** (or **Esc**) | Closes the stack and stops any live log stream | Always |

**Esc** only closes the stack when nothing is capturing it: it does nothing while the palette is open, or while a text field or the log view has focus.

## Tabs

Data loads when a tab first needs it and is cached until you refresh or open another stack.

### Overview

Cards for the stack: name, state, description and labels; VCS settings (provider, repository, branch, commit and message); backend; settings (autodeploy, autoretry, worker pool, runner image and so on); attached contexts (names only, expandable); and attached policies.

At the top is the **Latest tracked run** card: the newest run that was actually deployed, with its type, state, trigger, title, commit and whether it needs approval. If the stack has no tracked run but has other runs, the card is titled **Latest run** and shows the newest of those. If the stack has never run, it shows "No runs" (see [Never-run stacks](#never-run-stacks)).

### Run history

The top half is the list of runs; the bottom half shows the **changes** of the selected run, with a header naming the run. Drag the divider to resize.

**What is listed.** The latest 10 tracked runs and the latest 10 proposed runs (which include drift detection), merged and sorted newest first.

| Column | Meaning |
|---|---|
| ⓘ | Opens the run details popover |
| Run | Run ID |
| Type | **Tracked** (a deployment), **Proposed** (a preview, for example from a pull request) or **Drift** (a drift-detection run) |
| State | Run state |
| When, Trigger, Author, Title | Creation time, what started it, commit author, run title |

**Filter.** An All / Tracked / Proposed / Drift switch appears above the list only when the stack has runs other than tracked ones.

**Selecting a run.** A single click selects it. The selection sets the run shown in the changes pane and in the **Logs** and **Live logs** tabs. With nothing selected, the default is the **latest tracked run**.

**Changes pane.** Shows the resource changes of the selected run. A run with no changes (for example a drift run that found none) shows "No resource changes for this run".

**Opening a run.**

- **Double-click** a run, or right-click > **Open logs**: jumps to the Logs tab for that run.
- Right-click > **Follow live**: jumps to Live logs. Enabled only for runs still in progress.
- Right-click > **Details**, **⌘I**, or the ⓘ button: a popover with run ID, type, state, who triggered it and when, title, commit and approval status.
- Right-click > **Retry failed run**: see [Retry](#retry-failed-run). Shown only with actions enabled and only on failed runs.

### Logs

Static logs of one run.

- **Run** picker: any run in the list (shown with its type and state). It starts on the run selected in Run history, or the latest tracked run.
- **Phase** picker: All phases, or one of Queued, Preparing, Initializing, Planning, Applying, Finished.
- Each phase starts with a **colored heading** with extra spacing: gray (Queued, Ready), teal (Preparing), blue (Initializing), violet (Planning), yellow (waiting for confirmation), orange (Applying), green (Finished), red (Failed).
- **Auto-scroll** follows new output. **⌘F** opens find.

### Live logs

Follows a run as it happens (`spacectl ... --tail`), so it is a stream and not polling. It uses the same run picker. **Stop** ends the stream, and **Follow again** restarts it. Closing the stack or switching runs stops it.

### Outputs

The stack's outputs, flattened to rows (output, path, value) with a filter box. Sensitive outputs are not shown.

### Environment

Environment variables (name, type, value, context). Write-only values show `*****`, and values computed at runtime show `<computed>`.

### Everything

Overview, changes, run history, outputs and environment on one scrollable page (everything except logs).

### Never-run stacks

A stack that has never run shows "No runs" in Overview and Run history. With actions off, the message points to Settings. With actions on, there is a **Trigger** button; see below.

## Actions (off by default)

The app is read-only until you turn actions on: **Settings (⌘,) > Enable actions**. With the setting off, none of the controls below appear. Turning it off while a batch is running stops the batch.

All actions:

- run as you, using your Spacelift permissions, and are recorded in Spacelift under your name;
- ask for confirmation first;
- never use `--auto-confirm` or `--force-apply`. A new run applies by itself only if the stack has **autodeploy** on; otherwise it waits for a person to confirm it in Spacelift.

### Trigger button (first run)

Starts a new tracked run at the branch head (`spacectl stack deploy`), like the Trigger button in the Spacelift web UI.

- **Available when:** actions are enabled, you have write permission on the stack, and the stack has **no tracked run** (it has never been deployed). A stack with only proposed or drift runs still counts as never deployed.
- **Greyed out when:** the runs are still loading, you lack permission, or the stack already has a tracked run. The tooltip says which. To start another run for a stack that has run before, use the [Trigger tab](#trigger-tab-many-stacks).
- A confirmation dialog names the stack and warns if autodeploy is on ("the run will apply immediately"); otherwise it says the run waits for confirmation.
- After it starts, the app refreshes the stack and opens Run history.

### Retry failed run

Repeats a failed run (`spacectl stack retry`) at its original commit.

- **Available when:** actions are enabled and the run's state is **Failed**. Right-click the run in Run history.
- A confirmation dialog names the stack and the run.
- It is different from Trigger: Retry repeats that run, while Trigger starts a new run at the branch head.

### Trigger tab (many stacks)

Triggers several stacks from a search. It is a segment in the sidebar's switch, visible only with actions enabled.

**What it lists.** The same search as the Search tab (2+ characters, up to 200 results), but only stacks that **have run before**. Stacks that have never run are hidden, with a note giving how many; start their first run from the Trigger button on their own page.

**Selecting.**

- Each row has a checkbox. **Nothing is selected until you select it.** Use **Select all** or **None**.
- Only the stacks currently in the results count. Ticks on stacks that a new search no longer shows are ignored.
- Row icons: ⚡ autodeploy is on (a new run applies immediately); ⌛ another run is blocking the stack (a new run queues behind it); 🔒 you lack permission (the row is disabled and can't be selected).
- With 200 results a warning asks you to narrow the search before using Select all.

**Confirming.** The **Trigger N stacks…** button opens a sheet that shows:

- the stack count and a scrollable list of all stack IDs;
- a warning listing the stacks with autodeploy ("will apply immediately");
- a warning listing stacks already blocked by another run;
- a text box where you must type either `deploy <count>` (the number of selected stacks) or `deploy <search>` (your current search text). Case and extra spaces are ignored. The Trigger button stays disabled until it matches.

Typing the search text does not check how many stacks you ticked, so read the count at the top of the sheet.

**Running.** Once confirmed, the sidebar switches to a progress list. At most **3 runs are in progress at once**: the next stack starts when one settles, to avoid flooding the runners. A run counts as settled when it reaches Finished, Failed, Discarded, Canceled, Stopped, Skipped, or a state waiting for a person (Unconfirmed, Pending review). Each row shows:

| Status | Meaning |
|---|---|
| Queued | Not started yet |
| Starting… | The trigger command is running |
| a state pill with a spinner | The run was created and is progressing |
| a final state pill | The run settled |
| a red message | The trigger failed, with the error from `spacectl` |
| "Stopped waiting" | You pressed Stop; the run keeps going in Spacelift |
| Not started | The batch was stopped before this stack |

Click a row to open that stack. **Stop** stops starting new stacks and stops waiting on running ones; it does **not** cancel runs already created. **Done** appears when the batch ends. It returns to the list and refreshes the stack states.

**Limits.** The batch lives in the app: closing the app stops the waiting (runs already created continue in Spacelift). A run held up by another blocking run keeps its slot until it settles.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘K | Command palette |
| ⌘R | Refresh the open stack |
| ⌘I | Run details (Run history tab) |
| ⌘F | Find in logs |
| ⌘, | Settings |
| Esc | Close the palette, a sheet or dialog, or the open stack (see [Stack header](#stack-header)) |

## Stored data and reset

The app stores two things in macOS preferences under `io.github.luispcoutinho.spacectl-ui`: the recent stacks (IDs and times) and the "Enable actions" setting. It stores no credentials; authentication belongs to `spacectl`.

To reset everything:

```bash
defaults delete io.github.luispcoutinho.spacectl-ui
```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "spacectl not found" | Install `spacectl` and make sure it is in one of the locations listed above. |
| Search or load errors mentioning login | Run `spacectl profile login <subdomain>` in a terminal. |
| Search shows nothing | Type at least 2 characters. Only the first 200 matches are returned. |
| macOS refuses to open the app | Clear the quarantine flag (see the README). |
| No Trigger tab, button or Retry item | Actions are off. Enable them in Settings (⌘,). |
| Trigger button greyed out | The stack already has a tracked run, you lack permission, or runs are still loading. Hover for the reason. |
| A stack is missing from the Trigger tab | It has never run (use its own Trigger button), or it is not in the first 200 results. |
| Proposed or drift runs missing | Only the latest 10 of each kind are fetched. Use the filter, or look in Spacelift for older ones. |
| "Action failed" alert | The text is the error from `spacectl`: permissions, a locked or disabled stack, or a policy rejection. |
