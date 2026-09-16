# Agents

One bar icon and one panel for every AI coding subscription on the machine.

The panel is a balance sheet, not a dashboard: a subscription shows how much of
its allowance is gone and when the window comes back, and a pay-per-token
account shows what is left on the meter. One row per subscription, all on
screen at once.

This is a **clone** of the built-in `omarchy.agents` plugin. `Panel.qml` owns
the bar button and the popup; `Main.qml` discovers and watches the records;
`Agent.qml` is the per-record file watcher. Everything below is specific to the
clone.

> **Changing this plugin's QML needs a shell restart.** Saving a file under
> `~/.config/omarchy/plugins/` reloads plugin code, but on this shell version
> the bar widget's component is reused rather than recompiled, so edits to
> `Panel.qml` or `Main.qml` only take effect after `omarchy restart shell`.
> Collector scripts are ordinary executables and are picked up immediately.

## Panel

- **One row per subscription**, each with its mark, its name, and its plan
  underneath. Subscriptions come first, then prepaid accounts, each group
  alphabetical — a subscription is paid for whether or not you use it, while a
  prepaid balance only costs what you spend. The grouping is read off each
  record, so a card moves between groups on its own the day it starts reporting
  something new.
- **Clicking a card opens it in place**, like a `<details>` element: a link to
  that provider's billing page, a funded amount where the balance is an
  estimate, and **Move to top / Move to bottom**. One card at a time, and
  opening the panel collapses everything.
- **Reordering stays inside a group.** The group answers "what can I still
  lose?", so it is the rule rather than a default to be buried; the stored order
  decides the sequence within a group. A provider that appears after the last
  reorder keeps its alphabetical place at the end of its group until the next
  move rewrites the list.
- **Prepaid accounts** show what is left and what has been spent, with a meter
  that drains toward empty.
- **Subscriptions** show one line per rolling window (`5h`, `7d`, `30d`): a bar,
  and the time until it resets. The bar *is* the percentage, so the number is
  not repeated beside it — label, bar, and countdown all line up across windows,
  which is what makes three of them scannable at a glance. The fullest window
  keeps full contrast because it is the one that will stop the next prompt.
- **A card we cannot read collapses to its mark**, in a row of linked buttons
  along the bottom. Fireworks gates its ledger to the dashboard, Claude Code
  reports nothing until it is signed in, and Replicate publishes no balance at
  all, so there is no figure to draw — but there is a page that has it.
- **Every card is a link.** Clicking anywhere on a row, or on a bottom button,
  opens that provider's own usage or billing page with
  `omarchy-launch-browser` and closes the panel. The URLs live in
  `Panel.qml`'s `billingUrl()`; that map is the one place to edit.
- The bar dot lights when any window passes 90% or any prepaid account drops to
  its last 10%.

The row/button split is computed, not configured: a card grows into a row as
soon as it has a balance or a window to show. GitHub Copilot stays off, so the
current rows are OpenAI, OpenCode Go, DeepSeek, Fireworks and OpenRouter, with
Claude, Replicate and OpenCode Zen as buttons.

`j`/`k` or arrows scroll, `r` or Enter refreshes, Tab moves to the neighboring
bar panel, Esc closes. IPC: `omarchy-shell omarchy.agents
<open|close|toggle|refresh|next>`.

## Data

Each agent is one JSON record in `~/.local/state/omarchy/agents/usage/`. The
widget invokes `bin/omarchy-agents-refresh` on its refresh timer and whenever
you ask for a refresh, and picks up any record that lands in the directory.

That wrapper runs the upstream collectors (`omarchy-agent-usage-update`, which
covers **Claude**, **Codex**, and **Fireworks**) alongside this plugin's
`bin/omarchy-agent-usage-opencode`, which covers everything else. It accepts the
same arguments as the stock command (`--force`, `--limits-only`, `--except
<agent>`, an explicit agent list) and is not required: without it the upstream
records still refresh.

The two sides run at once and write **disjoint records** — one writer per file —
so neither waits on the other. That matters because the upstream claude
collector can take ~30s walking an 8.9 GB database, and the rows this plugin
owns should not be held hostage to it. Measured: every record this plugin writes
lands at **t+2s**, whatever the upstream side is doing.

A provider that is switched on in settings is listed even before its records
exist, so the list never grows or reorders itself mid-refresh — the rows are
there from the first frame and their numbers fill in.

| Card | Windows | Balance | Sessions |
|---|---|---|---|
| OpenAI | 5h + 7d, from the ChatGPT backend | — | opencode (`openai`, `codex` folded in) |
| DeepSeek | — | live, `api.deepseek.com/user/balance` | opencode |
| OpenCode Go | 5h + 7d + 30d, from `opencode.ai/zen/go/v1/usage` | — | opencode (`opencode-go`) |
| OpenCode Zen | none published | none published | opencode (`opencode`) |
| OpenRouter | — | live, `openrouter.ai/api/v1/credits` | opencode |
| Fireworks | — | estimated (upstream; needs `fundedAmount`) | opencode |
| Claude Code | 5h + 7d, from Anthropic's OAuth endpoint | — | upstream |
| Replicate | — | none published | opencode |

The last three have no readable figure and render as linked marks. Claude's row
would fill in if it were signed in — its collector reports nothing while logged
out, which is why it currently shows a mark instead.

**Go and Zen are separate cards**, because a card is one account you owe and one
card cannot be two things: Go is a subscription with rolling windows, Zen is a
credit balance. Go shows its three windows; Zen has no API at all, so it has no
figure to show and collapses to its mark like the other unreadable accounts.

**A card with no figures still gets a record**, emitted blank so the panel has
something to hang a mark on. That is why "no data" is a record rather than a
missing file.

## The OpenAI card

The OpenAI card is built here rather than by the upstream codex collector,
because that collector reads the Codex CLI's app-server RPC — and that RPC needs
`codex login`, while **connecting Codex in opencode's TUI stores an OAuth
credential in opencode's database instead, leaving no `~/.codex/auth.json` at
all**. The CLI then reports an empty record while a working subscription sits
right there.

So this collector reads opencode's `openai` credential (or `~/.codex/auth.json`
if the CLI is logged in) and asks the ChatGPT backend for the account's rolling
windows. opencode sessions running on the `openai` providerID land on the same
card, as does a `codex` providerID if one ever appears — both names describe one
subscription. The wrapper passes `--except codex` to the upstream command, so
exactly one collector writes that file; two writers meant the row blanked out
whenever the upstream one won.

## The opencode collector

opencode is where the pay-per-token subscriptions are actually spent, and it
keeps its own books, so one pass over its database covers every provider at
once.

| providerID in opencode | Card |
|---|---|
| `deepseek` | DeepSeek |
| `openrouter` | OpenRouter |
| `opencode-go` | OpenCode Go |
| `opencode` | OpenCode Zen |
| `openai` | OpenAI |
| `codex` | OpenAI *(folded — both names are one subscription)* |
| `github-copilot` | GitHub Copilot |
| `fireworks-ai` | *(skipped — the `fireworks` collector owns it)* |
| `anthropic` | *(skipped — the `claude` collector owns it)* |
| `ollama*`, `localhost`, `lmstudio`, `vllm`, `replicate` | *(skipped)* |

Skipping matters: counting a provider in two records would show every one of its
tokens twice.

Any providerID can be added, renamed, folded, or dropped without editing the
script:

```json
// ~/.config/omarchy/agents/opencode.json
{
  "providers": {
    "replicate": { "name": "Replicate", "tierLabel": "Prepaid" },
    "openrouter": { "enabled": false }
  }
}
```

### What the numbers come from

For session history, two tables — neither of them the 8.9 GB `message` table
the upstream claude/codex collectors walk:

| Table | Used for |
|---|---|
| `session_v2` | the session → providerID and model map |
| `part` (`type = "step-finish"`) | per-step tokens, and the timestamp that dates them |
| `session_message` (`type = "user"`) | prompt and session counts |

The panel no longer draws any of that, so it is there for the record contract
and for synced aggregation rather than for display. If you are sure you will
never want it, the scan is the expensive part of this collector and could go.

### Known limits

- **OpenCode Zen publishes no balance or usage API.** `zen/v1/balance` and
  `zen/v1/usage` both 404; an open feature request tracks it. Zen can report
  what it spent but not what is left.
- **GitHub Copilot's quota is not reachable here.** The usage endpoint requires
  a Copilot-entitled GitHub token, and no Copilot credential is stored by
  opencode on this machine.
- **Roughly 170M historical tokens are unattributed.** 42 sessions predate
  opencode recording a model at all.
- **Days before 2026-02-13 are unreliable** in the session history: older
  history was migrated into `part` rows stamped with the migration time.
- **Model attribution follows the session's model**, so a session that switched
  models counts all of its tokens toward the model it ended on.
- **opencode.ai sits behind Cloudflare and rejects a bare `Python-urllib` user
  agent** with 403. The collector identifies itself, as opencode's docs ask.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json`, set with
`omarchy bar set jace.agents <key> <value>`:

| Key | Default | What it does |
|---|---|---|
| `refreshIntervalSec` | `900` | How often the records regenerate |
| `syncMode` | `"Off"` | `"On"` writes this machine's snapshot and merges the others |
| `syncDir` | `""` | A folder synced by Syncthing, Dropbox, rsync, … |
| `syncFileName` | `<hostname>.json` | This machine's snapshot file |
| `syncDeviceId` | hostname | Stable device name inside the snapshot |

Numbers need `--json`, or they land in `shell.json` as strings:

```bash
omarchy bar set jace.agents refreshIntervalSec 300 --json
```

**Row order** is computed, not configured: subscriptions before prepaid accounts
(same rule as above), each group alphabetical. Use **Move to top / Move to
bottom** on a card to override it, which writes the plugin's own config:

```jsonc
// ~/.config/omarchy/agents/opencode.json
{
  "providers": { "github-copilot": { "enabled": false } },
  "order": ["opencode-go", "openai", "deepseek", "fireworks", "openrouter"]
}
```

It lives there rather than in the widget's settings because `omarchy bar set`
cannot store an array: a two-element array is rejected by the shell's IPC, and a
one-element array is silently stored as a bare string.

`enabled` decides whether a card is drawn at all; omitting a provider leaves it
enabled:

```bash
omarchy bar set jace.agents providers '{
  "openai": { "enabled": true },
  "opencode-go": { "enabled": true },
  "deepseek": { "enabled": true },
  "openrouter": { "enabled": true },
  "fireworks": { "enabled": true },
  "github-copilot": { "enabled": false }
}' --json
```

`enabled: false` hides a subscription that is installed. Disabled agents are
also skipped when the records regenerate.

## Assets

`assets/<id>.svg` is the mark for dark surfaces, with an `assets/<id>-light.svg`
twin for light ones; a brand-coloured mark that works on both ships one file.
A missing mark is not an error — the bar glyph stands in. The DeepSeek,
OpenRouter, OpenCode, GitHub Copilot, and Replicate marks come from
[Simple Icons](https://simpleicons.org) (CC0). Simple Icons no longer ships the
OpenAI mark, so that one comes from [thesvg.org](https://thesvg.org/icon/openai).
