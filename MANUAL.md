# Spacelift Stacks: user manual

This manual describes every feature of the app, how each one behaves, and the conditions under which it is available. For installation and build instructions, see the [README](README.md).

The app is a front end for [`spacectl`](https://github.com/spacelift-io/spacectl). It runs `spacectl` commands as you, so it shows only what your Spacelift account can see, and every action it can take uses your own permissions. It has no login of its own.

## Contents

1. [Quick start](#quick-start)
2. [Concepts and glossary](#concepts-and-glossary)
3. [The window](#the-window)
4. [Finding stacks](#finding-stacks)
5. [Command palette](#command-palette)
6. [Stack header](#stack-header)
7. [Tabs](#tabs)
8. [Actions (off by default)](#actions-off-by-default)
9. [How do I...? (recipes)](#how-do-i-recipes)
10. [How the app gets its data](#how-the-app-gets-its-data)
11. [Keyboard shortcuts](#keyboard-shortcuts)
12. [Stored data and reset](#stored-data-and-reset)
13. [Limits](#limits)
14. [Troubleshooting and FAQ](#troubleshooting-and-faq)

## Quick start

1. Install `spacectl` and log in: `spacectl profile login <your-spacelift-subdomain>`. Check it works with `spacectl stack list --limit 1`.
2. Open the app. If macOS blocks a downloaded copy, clear the quarantine flag once (see the README).
3. Type at least 2 characters of a stack name in the search box and click a result.
4. Use the tabs on the right: **Overview** for settings and the latest deployment, **Run history** for runs and their changes, **Logs** for a run's output.
5. Press **⌘K** at any time to jump to a recent stack or a tab.

Everything above is read-only. Starting or retrying runs is a separate, opt-in feature (see [Actions](#actions-off-by-default)).

## Concepts and glossary

**Stack.** A Spacelift unit of infrastructure code, with a repository, a branch and a state. Stack IDs are the slugs you see in Spacelift, for example `my-team_prod_eu_vpc`.

**Run.** One execution of a stack. The app shows three types, derived like this:

| Type | What it is | How the app knows |
|---|---|---|
| **Tracked** | A deployment: plan, then apply, from the stack's tracked branch | Returned by the default `spacectl` run list |
| **Proposed** | A preview (plan only, nothing applied), for example for a pull request | Returned only when `spacectl` is asked for preview runs |
| **Drift** | A drift-detection run: a scheduled plan that checks whether real infrastructure moved away from the code | A preview run flagged as drift detection |

Drift runs are plans, so they never apply anything. Spacelift can optionally react to drift by starting a tracked run (a setting on the stack, not part of this app).

**State.** Where a run or stack is in its life. The app shows the state as a colored pill (and as a colored dot in lists):

| Color | States | Meaning |
|---|---|---|
| Green | Finished | Completed successfully |
| Red | Failed | Ended with an error |
| Orange | Unconfirmed, Pending review | Waiting for a person to confirm or review |
| Violet | Queued, Ready, Preparing, Preparing apply, Initializing, Planning, Performing, Applying, Destroying, Confirmed, Pending | In progress or about to start |
| Gray | Discarded, Canceled, Stopped, Skipped | Ended without finishing |
| Neutral | anything else, including **None** | Unknown to the app |

A stack with the state **None** has never run a tracked run. States are shown title-cased with underscores turned into spaces ("Pending review").

**Autodeploy.** A stack setting. With it on, a tracked run applies as soon as its plan succeeds. With it off, the run stops at Unconfirmed until a person confirms it. This decides how dangerous an action is, which is why the app warns about it.

**Blocker.** Another run currently holding the stack. A new run for a blocked stack queues until the blocker ends.

**Settled.** The app's word for a run that needs nothing more from the machine: Finished, Failed, Discarded, Canceled, Stopped, Skipped, or waiting for a person (Unconfirmed, Pending review). Used by the batch throttle.

**Never-run stack.** A stack with no tracked run. In the Trigger tab it is hidden when the action is Deploy (its first deployment is started from its own page), but listed when the action is Preview.

## The window

- **Left pane:** finding stacks. A **Search | Recent** switch, plus a **Trigger** segment when actions are enabled. The footer shows how many stacks are listed, a **Clear history** link in Recent, and a ⌘K button.
- **Right pane:** the open stack: a header, a row of tabs, and the tab's content. With no stack open it shows "Select a stack".
- The app uses a dark theme. The minimum window size is 1200 by 650.

## Finding stacks

### Search

- Search runs on the server, because listing every stack takes minutes. It needs at least **2 characters** and starts about 0.4 seconds after you stop typing.
- The text is passed to Spacelift's own stack search, so what matches is decided by Spacelift.
- Results are limited to **200**, sorted by ID. If you see 200, narrow the search.
- Each result shows a colored state dot, the stack ID, the state and the author of the tracked commit.
- Click a result to open it. The × inside the search field clears the text.

### Recent

- Lists the last **30** stacks you opened, newest first, without duplicates ("Opened 2 hours ago", or "just now" under a minute).
- A stack is recorded whenever it becomes the open stack, however you opened it (search, Recent, or the palette).
- Only the stack **ID and the time** are stored, never a state, so nothing shown is stale. The live state loads when you open the stack.
- Right-click an entry to **Remove from history**, or use **Clear history** in the footer.
- If a recent stack no longer exists, opening it shows the error `spacectl` returns.

## Command palette

Press **⌘K** (or click the ⌘K button in the sidebar footer). Press ⌘K again or Esc to close it.

| What you type | What you get |
|---|---|
| Nothing | If a stack is open: the tab names and Refresh. Then your 8 most recent stacks, then the stacks currently listed in the sidebar search (up to 30) |
| 1 character | The same list, filtered locally |
| 2 or more characters | The same, plus a server search for stacks (up to 30), after a 0.3 second pause |

Items are tagged **Tab**, **Action** (Refresh), **Recent** or **Stack**. Use **↑ ↓** to move, **↵** to run the highlighted item and **Esc** to close. Typing several words requires all of them to match.

The palette opens stacks and jumps between tabs. It never starts or retries runs.

## Stack header

Shows the stack ID (selectable, so you can copy it), `repository · branch`, and the state pill. The state is the live state once the stack has loaded. Buttons on the right:

| Button | What it does | Availability |
|---|---|---|
| **Trigger** | Starts the stack's first run | Only with actions enabled; see [Trigger button](#trigger-button-first-run) |
| **Refresh** (⌘R) | Discards the cached data for the open stack and reloads the current tab | Always |
| **×** | Closes the stack and stops any live log stream | Always |

**Esc** does the same as ×, but only when nothing else needs it: it does nothing while the palette is open, or while a text field or the log view has keyboard focus (so Esc in a text box still means "cancel typing").

## Tabs

The tabs are: **Overview, Run history, Logs, Live logs, Outputs, Environment, Everything**. Data loads when a tab first needs it and is cached until you refresh or open another stack. Each tab shows a spinner while loading and the error from `spacectl` if it fails.

### Overview

At the top, the **Latest tracked run** card: the newest run that was actually deployed.

| Field | Meaning |
|---|---|
| Run | The run ID |
| Type | Tracked, Proposed or Drift |
| State | Its state, plus "(most recent)" when Spacelift marks it so |
| Triggered | What started it (a user, a push, a schedule) and when |
| Title | The run's title, usually the commit or pull request title |
| Commit | Short hash and author |
| Approval | Whether the run needs approval |

If the stack has no tracked run but has other runs, the card is titled **Latest run** and shows the newest of those. If the stack has never run it shows "No runs" (see [Never-run stacks](#never-run-stacks)).

Below it are cards for the stack itself:

- **Stack:** name, state, when the state was set, description and labels.
- **VCS settings:** provider, repository, branch, the tracked commit (hash, author) and its message.
- **Backend:** the vendor (for example Terraform or OpenTofu), its settings, and whether Spacelift manages the state.
- **Settings:** administrative, worker pool (or "public"), autodeploy, autoretry, local preview, project root, extra project globs, runner image and Terraform version.
- **Attached contexts:** each context with its item count. Expand one to see item names. Values are never shown.
- **Attached policies:** name and type of each attached policy.

### Run history

The top half is the list of runs; the bottom half shows the **changes** of the selected run, under a header that names the run. Drag the divider to resize the halves.

**What is listed.** The latest **10 tracked** runs and the latest **10 proposed** runs (drift runs are among the proposed ones), merged, de-duplicated and sorted newest first.

| Column | Meaning |
|---|---|
| ⓘ | Opens the run details popover |
| Run | Run ID (selectable text) |
| Type | A pill: Tracked, Proposed or Drift |
| State | The state pill |
| When | Creation time, in your local time zone |
| Trigger | What started it, for example a user or `spacelift/drift_detection` |
| Author | Commit author |
| Title | The run's title |

**Filter.** An **All | Tracked | Proposed | Drift** switch appears above the list only when the stack has runs besides tracked ones. If a filter matches nothing it says "No drift runs" (and so on).

**Selecting a run.** A single click selects it. The selection decides which run the changes pane, **Logs** and **Live logs** show. With nothing selected, the default is the **latest tracked run** (or, if there is none, the newest run of any type).

**The changes pane.** Lists resource changes of the selected run: Change (create, update, delete and so on), Resource address and Previous address (for moved resources). Changes load when you select a run and are cached per run, so switching back and forth is instant. A run with no changes (for example, a drift run that found none) shows "No resource changes for this run".

**What you can do with a run**

| Gesture | Result | Condition |
|---|---|---|
| Double-click, or right-click > **Open logs** | Opens the Logs tab on that run | Always |
| Right-click > **Follow live** | Opens Live logs on that run | Enabled only for runs still in progress |
| Right-click > **Details**, **⌘I** or the ⓘ button | Popover with the run's fields (same as the Overview card) | Always |
| Right-click > **Retry failed run** | See [Retry failed run](#retry-failed-run) | Actions enabled and the run is Failed |

The ⓘ popover opens next to the row's own button. **⌘I** toggles it for the selected run. Click away or press Esc to close it.

### Logs

The recorded logs of one run, for reading after the fact.

- **Run** picker: any run in the list, shown as a short ID, type, state and time. It starts on the run selected in Run history, or the latest tracked run.
- **Phase** picker: All phases, or one of Queued, Preparing, Initializing, Planning, Applying, Finished. Changing it reloads the logs for that phase only.
- Spacelift prints a banner at the start of each phase. The app turns each banner into a **colored heading** with extra space above it, so phases are easy to tell apart:

| Phase | Heading color |
|---|---|
| Queued, Ready (and Discarded, Canceled, Stopped, Skipped) | Gray |
| Preparing | Teal |
| Initializing | Blue |
| Planning | Violet |
| Unconfirmed, Pending review, Confirmed | Yellow |
| Applying, Performing, Destroying | Orange |
| Finished | Green |
| Failed | Red |
| Any other phase | Purple |

Each heading shows the phase name and the timestamp Spacelift recorded. Everything else is plain monospaced text. Terminal color codes are stripped.

- **Auto-scroll** keeps the view at the newest line while output arrives.
- **⌘F** opens the find bar (case-insensitive incremental search). The text is selectable and copyable.
- Large logs load in batches, so the view stays responsive. Changing the run or the phase restarts the load.

### Live logs

Follows a run as it happens (`spacectl ... --tail`). It is a stream, not polling: new lines appear as Spacelift produces them.

- Uses the same **Run** picker and the same colored phase headings.
- **Stop** ends the stream; **Follow again** restarts it.
- Leaving the tab, closing the stack, refreshing or switching runs stops the stream.
- On a run that is already finished, it should simply replay the logs.

### Outputs

The stack's outputs, flattened into one row per value: **Output**, **Path** and **Value**.

- Structured outputs (objects and lists) are expanded into dotted paths, such as `vpc.subnets.0`. A plain value gets the path `-`.
- A filter box above the table narrows the rows by output name, path or value.
- Sensitive outputs are not returned by Spacelift, so they are not shown.

### Environment

The stack's environment variables: **Name**, **Type** (for example environment variable or mounted file), **Value** and **Context** (where it comes from). Write-only values show `*****`, and values computed at run time show `<computed>`. A filter box above the table narrows the rows by name, type, value or context.

### Everything

Overview, changes, run history, outputs and environment on one scrollable page (everything except logs). Its tables show the whole data, not scroll panes, so it is best for a quick scan or a screenshot.

### Never-run stacks

A stack with no runs shows **No runs** in Overview and in Run history. With actions off, the message says to enable actions in Settings (⌘,) to start the first run. With actions on, there is a **Trigger** button (enabled only if you have write permission).

## Actions (off by default)

The app is read-only until you turn actions on: **Settings (⌘,) > Enable actions**. With the setting off, none of the controls below appear at all. Turning it off while a batch is running stops the batch.

### Rules that apply to every action

- Actions run `spacectl` as you. They use **your** permissions, and Spacelift records them under your name.
- Every action **asks for confirmation** first.
- The app **never** passes `--auto-confirm` or `--force-apply`. A new run applies by itself only if the stack has **autodeploy** on; otherwise it waits at Unconfirmed for a person to confirm it in Spacelift.
- If `spacectl` fails (no permission, a policy rejection, a locked or disabled stack), an **Action failed** alert shows its error text, or the error appears next to the stack in a batch.

### What the app can and cannot do

| I want to... | In the app |
|---|---|
| Start the first run of a stack that never ran | **Trigger** button (header or empty state) |
| Start a new tracked run for a stack that has run before | **Trigger tab**, action **Deploy** (select just that stack) |
| Start new tracked runs for many stacks | **Trigger tab**, action **Deploy** |
| Start a preview (proposed run, plan only) on one or many stacks | **Trigger tab**, action **Preview** |
| Repeat a failed run | Right-click the run > **Retry failed run** |
| Replan, confirm or discard a run waiting for approval | Not supported: use the Spacelift UI or `spacectl stack replan`, `confirm`, `discard` |
| Cancel or stop a run | Not supported: use the Spacelift UI or `spacectl stack cancel` / `stop` |

### Trigger button (first run)

Starts a new tracked run at the branch head (`spacectl stack deploy`), like the Trigger button in the Spacelift web UI.

| Condition | Result |
|---|---|
| Actions off | The button does not appear |
| Runs still loading | Greyed out, tooltip "Loading runs…" |
| You lack write permission | Greyed out, tooltip says so |
| The stack already has a tracked run | Greyed out, tooltip points to the Trigger tab |
| The stack has no tracked run (never deployed) | **Enabled** |

A stack with only proposed or drift runs still counts as never deployed.

When you press it, a dialog names the stack. If the stack has autodeploy, it warns that the run **will apply immediately**; otherwise it says the run waits for a person to confirm. After the run starts, the app refreshes the stack and opens Run history, where the new run appears.

### Retry failed run

Repeats a failed run (`spacectl stack retry`) at its original commit.

- Right-click a **Failed** run in Run history. The item does not appear for other states, or with actions off.
- A dialog names the stack and the run ID.
- It differs from Trigger: Retry repeats that run, and Trigger starts a new run at the current branch head.

### Trigger tab (many stacks)

Starts a run on each selected stack. It is a segment in the sidebar's switch, visible only with actions enabled. A switch at the top picks the action for the whole batch:

| Action | What it starts | Command | Applies changes? |
|---|---|---|---|
| **Preview** (the default) | A **proposed run** at the branch head: a plan only | `spacectl stack preview` | Never |
| **Deploy** | A **tracked run** at the branch head | `spacectl stack deploy` | Yes, immediately on stacks with autodeploy; otherwise after a person confirms |

Preview is the default because it cannot change infrastructure. The line under the switch repeats what the chosen action does.

**What it lists.** The same search as the Search tab (2+ characters, up to 200 results). The search field is shared, so typing in one tab changes the other's results.

- **Preview** lists **every match**, including stacks that have never run (a preview works on any stack).
- **Deploy** lists only stacks that **have run before**. Never-run stacks are hidden, with a note saying how many; start their first run from the Trigger button on their own page.

**Selecting.**

- Each row has a checkbox. **Nothing is selected until you select it.** **Select all N** ticks every match in the list; **None** clears it. The header shows "N of M selected". "Every match" means every stack currently listed.
- Only stacks currently in the list count. If you change the search or switch the action, ticks on stacks that disappeared from the list are ignored.
- Row icons: **⚡** autodeploy is on (a Deploy applies immediately); **⌛** another run is blocking the stack (a new run queues behind it); **🔒** you lack permission (the row is disabled and cannot be selected).
- With 200 results, a warning asks you to narrow the search before using Select all.

**Confirming.** The **Preview N stacks…** or **Deploy N stacks…** button opens a sheet that shows the action, the stack count and a scrollable list of every stack ID.

- **Preview:** nothing else is needed. Press **Preview** to start. The sheet says that nothing is applied.
- **Deploy:** the sheet also warns about stacks with autodeploy ("will apply immediately") and stacks already blocked by another run, and asks you to type one of two phrases: `deploy <count>` (the number of selected stacks) or `deploy <search>` (your current search text). Case and extra spaces are ignored. The **Deploy** button stays disabled until the text matches. Typing the search text does not check how many stacks you ticked, so always read the count at the top of the sheet. If the search text is empty, only the count phrase is offered.

**Running.** After you confirm, the sidebar shows a progress list headed "Previewing" or "Deploying". At most **3 runs are in progress at once**: the next stack starts only when one of the three settles. This protects the runners from a flood of simultaneous runs, which matters most for a preview over many matches. A run that is waiting for a person (Unconfirmed, Pending review) counts as settled, so the batch does not stall on it. Each row shows one of:

| Status | Meaning |
|---|---|
| Queued | Not started yet |
| Starting… | The command is running |
| A state pill with a spinner | The run was created and is in progress (checked every 10 seconds) |
| A final state pill | The run settled |
| A red message | The command failed, with the error from `spacectl` |
| "Stopped waiting; the run continues in Spacelift" | You pressed Stop while it was running |
| Not started | The batch was stopped before this stack |

- Click a row to open that stack on the right.
- **Stop** stops starting new stacks and stops waiting on running ones. It does **not** cancel runs already created; they carry on in Spacelift.
- When the batch ends, **Done** returns to the list, clears the selection and refreshes the stack states.
- You can switch to Search or Recent meanwhile; the batch keeps running while the app is open.

**Limits.** The batch lives in the app. Quitting it stops the waiting (runs already created continue in Spacelift, and nothing else is started). A run held up behind a blocking run keeps its slot until it settles. A preview is still a real run: it uses runner time and may trigger notifications or policies, so keep the search narrow.

## How do I... (recipes)

**Find why the last deploy failed.** Open the stack > **Run history** > double-click the failed run > in **Logs**, pick the **Planning** or **Applying** phase and look for the error. The **Failed** heading is red.

**See what a run changed.** Run history > click the run > read the changes pane under the list.

**Check for drift.** Run history > filter **Drift** > select the newest drift run. An empty changes pane ("No resource changes") means no drift was found; changes listed are the drift.

**Watch a deployment live.** Run history > right-click the run > **Follow live** (enabled while it is in progress).

**Find a stack I opened yesterday.** Left pane > **Recent**, or press **⌘K** with an empty box.

**Look up an output.** Open the stack > **Outputs** > type in the filter box.

**Start the first run of a new stack.** Settings > Enable actions. Open the stack > **Trigger** > confirm. Read the dialog: if autodeploy is on, it applies at once.

**Re-run a failed deployment.** Enable actions. Run history > right-click the failed run > **Retry failed run** > confirm.

**Redeploy a stack that has run before.** Enable actions. Sidebar > **Trigger** tab > switch to **Deploy** > search the stack name > tick only that stack > **Deploy 1 stack…** > type `deploy 1` > Deploy.

**Preview every match of a search.** Enable actions. Sidebar > **Trigger** tab > keep **Preview** selected > search a common word > **Select all N** > **Preview N stacks…** > Preview. The progress list shows each plan as it settles. Nothing is applied.

**Deploy a group of stacks.** Sidebar > **Trigger** tab > switch to **Deploy** > search a common word > review the list > tick the ones you want (or **Select all N**) > **Deploy N stacks…** > read the autodeploy and blocker warnings > type `deploy <N>` > Deploy. Watch the progress list; press **Stop** to end it early.

## How the app gets its data

Every read is a `spacectl` command. The app never contacts Spacelift directly.

| What you see | Command | When it runs |
|---|---|---|
| Search results | `stack list --search <text> --limit <n>` | After you stop typing (2+ characters) |
| Header and Overview cards | `stack show` | When a stack opens, and on Refresh |
| Run history, latest run | `stack run list` (tracked) and `stack run list --preview-runs` (proposed and drift), in parallel | Overview, Run history, Logs and Live logs; and for every tab when actions are enabled |
| Changes pane | `stack changes --run <id>` | When you select a run (cached per run) |
| Logs | `stack logs --run <id> [--phase <p>]` | When you open Logs or change run or phase |
| Live logs | `stack logs --run <id> --tail` | When you open Live logs |
| Outputs | `stack outputs` | Outputs and Everything |
| Environment | `stack environment list` | Environment and Everything |
| Trigger and Deploy | `stack deploy` | After you confirm |
| Preview | `stack preview` | After you confirm |
| Retry failed run | `stack retry --run <id>` | After you confirm |

Notes:

- **Caching.** Each piece of data loads once per stack and is kept until you press **Refresh** (⌘R) or open another stack. Switching tabs does not re-fetch.
- **Refresh** clears everything for the open stack and reloads what the current tab needs.
- If the preview-runs call fails, the app still shows tracked runs.
- The sidebar never loads more than the search results. Opening a stack loads it on its own, so a stack opened from Recent shows its live state even if it is not in the search results.
- When a command prints an empty list as `null`, the app treats it as "no rows".
- Starting a run is not undone by closing the app or pressing Stop: the run exists in Spacelift once the command succeeds.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘K | Open or close the command palette |
| ⌘R | Refresh the open stack |
| ⌘I | Toggle run details (Run history tab) |
| ⌘F | Find in logs |
| ⌘, | Settings |
| ↑ ↓ ↵ | Move and choose in the palette |
| Esc | Close the palette, a sheet, a popover or a dialog; with none open, close the stack (see [Stack header](#stack-header)) |

## Stored data and reset

The app stores two things in macOS preferences under `io.github.luispcoutinho.spacectl-ui`: the recent stacks (IDs and times) and the "Enable actions" setting. It stores no credentials: authentication belongs to `spacectl` and its own configuration. It writes no files of its own.

To reset everything (history, and actions back to off):

```bash
defaults delete io.github.luispcoutinho.spacectl-ui
```

## Limits

| Limit | Value |
|---|---|
| Search characters needed | 2 |
| Search results | 200 |
| Palette stack results | 30 |
| Recent stacks kept | 30 |
| Runs fetched per type | 10 tracked and 10 proposed (including drift) |
| Runs in progress at once in a batch | 3 |
| Batch state check interval | 10 seconds |
| Minimum window size | 1200 by 650 |

## Troubleshooting and FAQ

| Symptom | Cause and fix |
|---|---|
| "spacectl not found" | Install `spacectl` and make sure it is in one of the locations in the README. The app does not use your shell's PATH. |
| Errors mentioning login or authentication | Run `spacectl profile login <subdomain>` in a terminal, then Refresh. |
| Search shows nothing | Type at least 2 characters. Only the first 200 matches come back; narrow the search. |
| macOS refuses to open the app | Clear the quarantine flag once (see the README). |
| No Trigger tab, header button or Retry item | Actions are off. Enable them in Settings (⌘,). |
| Header Trigger button greyed out | The stack already has a tracked run, you lack permission, or runs are still loading. Hover over it for the reason. |
| A stack is missing from the Trigger tab | With **Deploy**, a stack that has never run is hidden (use its own Trigger button, or switch to Preview). Otherwise it is outside the first 200 results. |
| A row in the Trigger tab is disabled | You lack write permission on that stack. |
| Proposed or drift runs are missing | Only the latest 10 of each kind are fetched. Use the filter, or look in Spacelift for older ones. |
| The "Latest tracked run" is older than the newest run | Correct: newer runs are proposed or drift runs, not deployments. Filter Run history to see them. |
| "Action failed" alert | The text is the error from `spacectl`: permissions, a locked or disabled stack, or a policy rejection. |
| A triggered run did not apply | The stack has autodeploy off. The run is waiting at Unconfirmed; confirm it in Spacelift. |
| A batch row says "A run was started but its ID could not be read" | The command succeeded but its output did not contain a run ID. Open the stack and check its runs before triggering again. |
| Logs are empty | The run may not have produced output yet (queued), or the chosen phase has none. Pick **All phases**. |

**Is anything I do here dangerous?** Reading is not, and a Preview only plans. A Deploy can apply infrastructure changes when autodeploy is on, so actions are off by default, every action asks for confirmation, and a batch Deploy lists every autodeploy stack by name and needs a typed phrase.

**Does the app change anything when it is closed?** No. Runs already started continue in Spacelift, and nothing new is started.

**Why can't I trigger a stack that has runs from its own page?** By design, the header Trigger button is only for first runs. Use the Trigger tab (Deploy) to start another tracked run on a stack that has run before, or Preview for a plan only.

**Is this an official Spacelift app?** No. It is unofficial and not affiliated with Spacelift.
