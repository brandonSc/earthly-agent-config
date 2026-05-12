# Bender Priorities-Driven Autonomy — Implementation Plan

**Status:** In progress — PR #15 (daily pickup) up; follow-up PRs to come.
**Owner:** TBD (handoff to implementing agent)
**Linear ticket:** TBD (create before starting)

---

## Summary

Build a priorities-driven autonomy system around Bender's lunar-lib work. One markdown file at `~/repos/BENDER-PRIORITIES.md` defines what matters this quarter, and four collaborating subsystems read it:

| Subsystem | Cadence | Behavior |
|---|---|---|
| **Daily ticket pickup** | Weekdays 09:00 NYC | Pick the highest-priority eligible Lunar-lib ticket, announce in Slack with reasoning + plan, soft-veto window, dispatch worker |
| **Backlog grooming** | Tue + Thu 09:00 NYC | Re-rank the open backlog against current priorities, propose priority shifts, post to Slack for review |
| **Weekly PM sweep** | Mon 14:00 UTC (already shipping) | Propose 5 new tickets to expand the backlog (existing `pm-sweep.sh` — left in place, just becomes priorities-aware) |
| **Ticket creation** | Anytime a worker calls `bender-linear-create-issue` in Lunar-lib | Worker reads priorities and annotates ticket with which priority it serves |

The goal is to shift Bender from "human assigns ticket → agent works" to "agent picks priority-aligned ticket → human can veto," with the priorities file as a single human-edited source of truth. This is a marketing-critical autonomy milestone for the lunar-probe launch — the journal of self-selected tickets shipped becomes the launch post's emotional climax.

## Context

Bender already runs a weekly PM sweep (`~/bender/server/scripts/pm-sweep.sh`) that *proposes* new tickets and waits for Brandon to approve before creating them. The new subsystems are different shapes:
- Daily pickup *picks existing tickets and starts work on them*, with a short veto window instead of explicit approval.
- Twice-weekly grooming *re-prioritizes existing tickets* — proposing label/priority changes for human approval, no auto-dispatch.
- Ticket creation is an *inline change to every worker* — they consult priorities before filing a new ticket.

Follow the PM sweep's general shape (cron → analyze → post to Slack → track thread → handle response) where applicable, but the action surface is different per subsystem.

---

## The priorities file (foundation — read by all subsystems)

A single markdown file at `~/repos/BENDER-PRIORITIES.md`, edited by Brandon directly. Sits next to `~/repos/BENDER-JOURNAL.md` (already loaded by every worker prompt — `context-builder.ts` lines ~113, 411).

### Format

```markdown
# Bender Priorities

Top priorities for autonomous work, in order. Bender reads this when:
- Picking a daily ticket (highest-priority ticket wins)
- Grooming the backlog twice a week (Tue/Thu)
- Creating a new ticket (annotate which priority it serves)

Edit this file directly; changes apply on the next run.

## Current priorities (high to low)

1. **Lunar-probes MVP working and releasable** — initial probe surface area + docs sufficient to demo and release
2. **Lunar-lib has an initial library of ~20 probes** — basic programming language practices like running linters when code is edited
3. **QA lunar-probe** — bug fixes, edge case coverage, release-blockers
4. **Lunar-lib collectors and policies work** — keep the existing plugin surface healthy
5. **Tech-debt across lunar-lib and lunar-probe** — refactors, deprecations, hygiene
```

### Loader (shared module)

Add `loadPriorities()` to `~/bender/server/src/context-builder.ts` next to `loadJournal()`:
- Tries `~/repos/BENDER-PRIORITIES.md` first.
- Returns a placeholder string if the file doesn't exist — never throws, never blocks.
- Cap is small enough that the full file is always inlined (priorities are 5-10 lines, not 90 days of journal entries).

### Where each subsystem reads it

- **Daily pickup** (`daily-pickup.ts` — see "Goal behavior" below): inject into the ranker prompt as ordered context.
- **Grooming** (new, see [Backlog grooming](#backlog-grooming-tuesday--thursday) below): the central input to the rank-and-propose step.
- **PM sweep** (`pm-sweep.sh` — small follow-on edit): inject into the new-ticket proposal prompt so suggested tickets advance current priorities, not random hygiene.
- **Workers creating tickets** (`buildNewSessionPrompt` / `buildResumedPrompt`): inline the file the same way `loadJournal()` is inlined today, plus a "before you file a Lunar-lib ticket, annotate which priority it serves" instruction.

### Reference reading before starting

- `~/bender/CLAUDE.md` — operational rules, plan-first workflow, journal pattern
- `~/bender/SELF-MAINTENANCE.md` — how to modify Bender's own code with deferred restart
- `~/bender/server/src/task-manager.ts` — worker dispatch + Sonnet router
- `~/.bender/scripts/pm-sweep.sh` — existing cron pattern to mirror
- `~/repos/BENDER-JOURNAL.md` — where pick decisions get logged

---

## Daily pickup — goal behavior

Every weekday at 09:00 America/New_York (13:00 UTC), Bender should:

1. Pull the backlog of the configured Linear project (`Lunar-lib`, UUID `d613fe57-e5c0-4cf7-9e25-65c9655ea9d8` — same project `pm-sweep.sh` operates on).
2. Filter to eligible tickets (see [Eligibility](#eligibility) below).
3. Load `~/repos/BENDER-PRIORITIES.md` and pass it as ordered context to the classifier model.
4. Have an LLM rank the remaining candidates and pick one, with reasoning that cites which priority the pick advances.
5. Post to a configured Slack channel in this format:

   > 🤖 Daily ticket pick — [ENG-123](url): *short title*
   >
   > **Why this one:** [1-2 sentence reasoning citing **priority alignment**, urgency, dependencies, scope]
   >
   > **Plan:**
   > 1. [step]
   > 2. [step]
   > 3. [step]
   >
   > Vetoing? React :no_entry: in the next 10 minutes. Otherwise I'm starting at HH:MM.

6. Call `bender-track-thread` so replies route back.
7. Wait 10 minutes. Re-check the message reactions and replies.
   - If any human reacted `:no_entry:` / `:stop:` / `:x:`, or replied "no" / "stop" / "wait" / "not yet" / "skip" → abort, post acknowledgment, exit cleanly.
   - If someone replied substantively (e.g. "do this instead", "different ticket", "change the plan to X") → do NOT auto-dispatch. Fall through to the normal Slack interaction path so the Sonnet router handles the conversation.
   - Otherwise → dispatch a worker on the selected ticket.
8. Append a journal entry to `~/repos/BENDER-JOURNAL.md` capturing the pick + reasoning + priority cited, regardless of whether work was dispatched.

---

## Eligibility

A ticket is *eligible* for autonomous pickup if ALL of:

- State is `Todo` or `Backlog` (NOT `In Progress`, `In Review`, `Done`, `Canceled`)
- Assignee is unassigned OR Bender (not assigned to a human)
- Priority is `Urgent`, `High`, or `Medium` (not `Low`, not `No priority`)
- Labels do NOT include any of: `needs-design`, `needs-pm-input`, `needs-discussion`, `spec`, `epic`, `do-not-auto-pick`
- Has no open blocking dependencies (Linear `blocked by` relationships)
- Description is non-empty (skip tickets with just a title — they need fleshing out first)
- Estimated effort, if set, is ≤ 5 (skip multi-day epics)
- Not created in the last 24 hours (give humans a day to triage new tickets before Bender grabs them)

If zero tickets are eligible, post a quiet single-line note in the channel ("No eligible tickets in the backlog today — taking the day off") and exit. Do not pick something marginal.

---

## Selection logic

Among eligible tickets, use the configured classifier model (Sonnet by default) to rank by:

1. **Priority alignment** (top of `BENDER-PRIORITIES.md` first; ticket whose subject matter or labels advance a higher-numbered priority wins). This is the new top-line signal — Linear priority becomes a tiebreaker rather than the primary sort.
2. Linear priority field (Urgent > High > Medium) as tiebreaker within the same BENDER-PRIORITIES alignment.
3. Age (older > newer, within same alignment + Linear priority).
4. Fit for autonomous execution (clear scope > vague scope, isolated changes > cross-cutting).

The LLM call should return:

- Picked ticket ID
- 1-2 sentence reasoning citing the priority it advances ("advances priority #2: initial library of ~20 probes — adds Python linter probe")
- Concise numbered plan (3-7 steps)

Use the existing classifier model from `config.json` rather than hardcoding.

---

## Worker dispatch

Reuse the existing worker dispatch path that handles "work" actions from Slack. The cleanest entry point is probably to construct an event that mimics a Slack `work` classification and feed it to the task manager — but the implementing agent should read `task-manager.ts` and pick the cleanest API surface. Avoid duplicating worker-spawn logic.

The dispatched worker should receive:

- Ticket ID and full description as context
- The plan posted to Slack (so it doesn't re-plan from scratch)
- The Slack thread TS for reply routing
- Standard environment for `bender/` work

---

## Veto detection

Re-fetch the Slack message after the wait window using the Slack API:

- `reactions.get` to see who reacted with what
- `conversations.replies` to see if anyone replied in-thread

### Veto signals (any → abort)

- Reaction `:no_entry:`, `:no_entry_sign:`, `:stop:`, `:x:`, `:hand:` from any human (ignore reactions from Bender itself)
- Reply containing any of: `no`, `stop`, `wait`, `not yet`, `skip`, `hold`, `veto`, `different`, `instead`, `not that one`, `pick another`
- Reply matching any human-direction pattern (e.g. "do X first", "different ticket") — these should not auto-dispatch even if not strictly a veto. Fall through to the Sonnet router.

If aborted, post a follow-up: *"Standing down. Pick me a different one or let me know what you'd rather I do."*

---

## Journal entry

Append to `~/repos/BENDER-JOURNAL.md`:

```
- YYYY-MM-DD: Daily pickup — chose ENG-XXX ("title"). Reasoning: [reason]. Outcome: [dispatched | vetoed by @user | aborted because X].
```

This is the public evidence we'll point at for the launch — the journal becomes the receipts. Make sure the entry is informative, not generic.

---

## Configuration

Add to `~/.bender/config.json`:

```json
{
  "daily_pickup": {
    "enabled": true,
    "schedule": "0 13 * * 1-5",
    "timezone": "America/New_York",
    "projects": [
      {
        "linear_project_id": "d613fe57-e5c0-4cf7-9e25-65c9655ea9d8",
        "slack_channel": "<TBD channel ID>",
        "veto_window_minutes": 10
      }
    ],
    "excluded_labels": ["needs-design", "needs-pm-input", "needs-discussion", "spec", "epic", "do-not-auto-pick"],
    "min_priority": "medium",
    "max_effort": 5,
    "min_age_hours": 24
  }
}
```

`d613fe57-e5c0-4cf7-9e25-65c9655ea9d8` is the Linear project UUID for **Lunar-lib** (same one `pm-sweep.sh` already scans). The array shape leaves room for adding more projects (e.g. a separate lunar-probe Linear project) later without a schema change.

---

## Files (daily pickup PR)

### Create

- `~/bender/server/scripts/bender-daily-pickup.sh` — cron entry + manual `--dry-run` CLI (symlinked to `/usr/local/bin/bender-daily-pickup` via `install-on-path.sh`)
- `~/bender/server/src/daily-pickup.ts` — core logic (Linear query, eligibility filter, LLM rank, Slack post, veto watch, dispatch, journal, idempotency state file)
- `~/bender/server/src/daily-pickup.test.ts` — vitest unit tests (eligibility filter, veto detection, rank parsing, message formatting, timezone rollover)
- `~/bender/server/vitest.config.ts` — new for this repo

### Modify

- `~/bender/server/src/config.ts` + `types.ts` — add `daily_pickup` config block + loader with defaults
- `~/bender/server/src/index.ts` — wire up `POST /internal/daily-pickup` (background + `?dry_run=1`)
- `~/bender/server/src/task-manager.ts` — expose public `dispatchSlackWork(event)` (calls existing private `handleSlackWork` directly; bypasses Sonnet classifier for events we've already decided are work)
- `~/bender/server/src/context-builder.ts` — add `loadPriorities()` next to `loadJournal()`; inject priorities into the daily-pickup ranker prompt
- `~/bender/server/package.json` + `tsconfig.json` — add vitest devDep, `npm test` script, exclude `*.test.ts` from `tsc` build output
- Crontab on the Bender VM — add the new daily entry

### Don't modify

- The Sonnet router prompt in `task-manager.ts` (this new path is additive, not a replacement)
- The existing PM sweep — leave it alone for this PR; the small priorities edit lands as a separate commit

---

## Edge cases to test

1. **Empty backlog** (zero eligible tickets) → quiet single-line post, no dispatch
2. **Backlog has one ticket but it's spec-stage** → filtered out, falls through to empty case
3. **Brandon vetoes within the window** → abort cleanly, journal entry says vetoed
4. **Brandon replies with a different ticket ID** → fall through to router, do not auto-dispatch
5. **Linear API down** → log error, journal it, do NOT silently skip the day
6. **Slack post fails** → retry once, then log + journal, do NOT dispatch (we need the veto channel to exist)
7. **Selected ticket gets assigned to a human during the veto window** → re-check assignment before dispatch, abort if it changed
8. **Daylight saving transition** → confirm cron timezone handling is correct
9. **Run on a holiday or weekend** — the cron schedule `1-5` covers weekdays; verify
10. **Two daily-pickup runs colliding** (e.g. one retrying due to transient failure) → idempotency check; don't pick + dispatch twice in the same day

---

## Acceptance criteria

- [ ] Cron runs at the configured time on weekdays
- [ ] Eligibility filter is implemented and matches spec
- [ ] Selection uses the classifier model and returns reasoning
- [ ] Slack post matches the format above
- [ ] Veto window honors reactions AND replies, with the patterns listed
- [ ] Worker dispatches via the existing worker-spawn path (no duplicate logic)
- [ ] Journal entry is appended in all outcomes (dispatched, vetoed, aborted, empty)
- [ ] Config-driven (no hardcoded project IDs, channel IDs, or thresholds)
- [ ] Unit tests cover eligibility filter + veto detection
- [ ] Manual trigger CLI works: `bender-daily-pickup --dry-run` (prints what would happen without posting or dispatching)
- [ ] PR description includes a screenshot of a real dry-run output against the lunar-probe backlog

---

## PR description template

```markdown
## Summary

Adds daily autonomous ticket pickup. Bender scans the lunar-probe backlog every weekday morning, picks the best eligible ticket, announces the pick with reasoning and plan in Slack, waits 10 min for veto, and dispatches if not vetoed.

## Changes

- New `daily-pickup.ts` module: eligibility filter, LLM-based selection, Slack veto window, worker dispatch
- New cron entry point `daily-pickup.sh`
- Config schema extension under `daily_pickup`
- Manual trigger CLI `bender-daily-pickup` (with `--dry-run`)
- Journal integration for every outcome

## Testing

- Unit tests for eligibility filter and veto detection
- Dry-run output included as PR screenshot
- Manually triggered against lunar-probe backlog — picked ENG-X, posted to #bender-pickups, [vetoed/dispatched]

## Related

Part of the lunar-probe launch autonomy track. Companion to (TBD: live dashboard ticket, auto-merge ticket).

*This fix was generated by AI.*
```

---

## Notes for the implementing agent

- Read `pm-sweep.sh` first — the structural pattern is what you want to mirror.
- The veto detection logic is the part most likely to have edge-case bugs. Lean toward false-positive (abort) over false-negative (dispatch when humans wanted veto).
- Don't reinvent the worker dispatch — read `task-manager.ts` and find the cleanest API to invoke an existing path.
- Plan-first: write a plan, post it in Slack, wait for Brandon's go-ahead before implementing.

---

# Backlog grooming (Tuesday + Thursday)

A separate cron job that runs every Tuesday and Thursday at 09:00 NYC (13:00 UTC) and:

1. Reads `~/repos/BENDER-PRIORITIES.md`.
2. Pulls the full Lunar-lib backlog from Linear (same query as `pm-sweep.sh`, scoped to non-completed issues).
3. Asks the classifier model: given the current priorities, propose a rank order for the backlog AND flag tickets whose Linear `priority` field disagrees with their alignment to BENDER-PRIORITIES.
4. Posts a Slack message in Brandon's DM thread with:
   - Top 10 tickets, sorted by proposed priority
   - Suggested label/priority changes ("ENG-XXX is currently P3 but advances priority #1 — recommend bumping to P2")
   - A short note explaining the rationale per item
5. Calls `bender-track-thread` so Brandon's reply routes back to the normal Slack flow. Brandon can accept changes with "all" / list of numbers / individual edits; Bender then applies them via Linear API.
6. Append journal entry: `- YYYY-MM-DD: Groomed Lunar-lib backlog. Top items: ... Suggested shifts: ...`

### Files

- **Create:** `~/bender/server/src/backlog-grooming.ts` — core logic
- **Create:** `~/bender/server/scripts/bender-groom-backlog.sh` — cron + manual trigger CLI
- **Create:** `~/bender/server/src/backlog-grooming.test.ts` — unit tests
- **Modify:** `~/bender/server/src/types.ts` — add a `grooming` block to config schema
- **Modify:** `~/bender/server/src/index.ts` — add `POST /internal/groom-backlog` endpoint
- **Modify:** Crontab on the Bender VM — add Tue+Thu entries

### Config

```json
{
  "grooming": {
    "enabled": true,
    "schedule": "0 13 * * 2,4",
    "timezone": "America/New_York",
    "linear_project_id": "d613fe57-e5c0-4cf7-9e25-65c9655ea9d8",
    "slack_dm_channel": "D0APBM155CP",
    "top_n": 10
  }
}
```

### Acceptance criteria

- [ ] Cron runs Tue + Thu at the configured time
- [ ] Reads priorities file and feeds into ranking prompt
- [ ] Proposes (does NOT apply unilaterally) priority/label changes
- [ ] Posts to Slack DM with top N items + suggestions
- [ ] Brandon's approval reply applies the changes via Linear API
- [ ] Journal entry every run, regardless of outcome
- [ ] Unit tests for: rank parsing, shift-detection ("Linear P3 but advances priority #1 → suggest P2"), approval reply parsing

---

# Priority-aware ticket creation (worker prompt + CLI)

Whenever a worker creates a Linear ticket in the Lunar-lib project (e.g. it discovers a gap during PR work and files a ticket), the worker must:

1. Read `~/repos/BENDER-PRIORITIES.md` — already inlined into every worker prompt next to the journal (see "The priorities file" section above).
2. Decide which numbered priority the new ticket serves.
3. Annotate the ticket description with a one-line header: `**Aligns with priority #N:** <priority name>`.
4. If the ticket doesn't fit any current priority cleanly, say so explicitly in the description: `**Priority alignment:** doesn't cleanly fit current priorities — file for future consideration.` (Don't force-fit.)

### Implementation

- **Modify:** `~/bender/server/src/context-builder.ts` — add `loadPriorities()` and inline it in `buildNewSessionPrompt` + `buildResumedPrompt` (same shape as `loadJournal`/`loadWorkerContext`). Add a short instruction block in both prompts:

  > **Priority alignment for new tickets:** When you file a Linear ticket in the Lunar-lib project (`bender-linear-create-issue --project c4a71ff10119`), read `~/repos/BENDER-PRIORITIES.md` and add a `**Aligns with priority #N:** <name>` line at the top of the description. Don't force-fit — if nothing fits, say so.

- **Modify:** `~/bender/server/scripts/bender-linear-create-issue.sh` — soft-validate that the description contains `Aligns with priority` when `--project` is the Lunar-lib UUID; warn (not error) if missing. Lets us catch drift without breaking workers that legitimately can't map a ticket to a priority.

### Acceptance criteria

- [ ] `loadPriorities()` added to `context-builder.ts` next to `loadJournal()`
- [ ] Both prompt builders inline priorities + the instruction line
- [ ] `bender-linear-create-issue.sh` warns when filing in Lunar-lib without a priority annotation
- [ ] Manual smoke: dispatch a worker that files a Lunar-lib ticket and confirm the ticket description has the alignment header

---

# PM sweep (existing — small follow-on edit)

`pm-sweep.sh` already runs Mondays and proposes 5 new tickets. The follow-on edit is small:

- Source `~/repos/BENDER-PRIORITIES.md` at the top of the cron prompt, alongside the existing codebase context.
- Add a rule to the prompt: "**Each proposal must advance one of the current priorities. State which one in the rationale.**"
- No new files; just edits to the inline prompt in `pm-sweep.sh`.

This stays a separate, small commit — it's the lightest of the four changes and could land in any of the three follow-up PRs.
