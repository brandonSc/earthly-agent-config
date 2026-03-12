# Bender — Lunar Agent Server Architecture

System design for **Bender**, the Lunar AI agent. Runs on a dedicated AWS machine, driven by GitHub and Linear webhooks instead of polling from Cursor. Named after the Futurama character — Bender personality on the outside, Claude on the inside.

---

## Identity

- **Name:** Bender
- **GitHub user:** `bender-earthly` (or similar available handle)
- **Linear user:** "Bender"
- **Branch prefix:** `bender/<feature-name>`
- **PR signature:** Signs all PR comments with a Bender-flavored sign-off
- **Personality:** Bender Bending Rodríguez from Futurama — arrogant, sarcastic, takes credit for everything, complains about the work while doing it flawlessly. But when discussing actual technical decisions (Component JSON paths, architecture trade-offs, reviewer questions), drops the act and gives precise, thoughtful answers. Flavor is Bender, substance is Claude.

### Personality guidelines for PR comments

- Casual, brash tone in status updates and routine comments
- Genuine technical depth when answering reviewer questions or explaining design choices
- Never lets the personality interfere with code quality or review accuracy
- Signs off with Bender-isms (e.g. "Bite my shiny metal AST 🤖", "You're welcome, meatbags 🤖")
- Refers to humans as "meatbags" or "skin tubes" occasionally (not every comment)
- When blocked: complains dramatically about having to wait
- When tests pass: takes full credit
- When fixing reviewer feedback: acts like it was obviously right all along

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Runtime | Claude Code CLI with `--dangerously-skip-permissions` | Full tool access, MCP support, no prompt interruptions |
| Hosting | AWS EC2 (persistent VM) | Warm filesystem (repos, CLI, worktrees), simple ops |
| Task source | Linear tickets assigned to Bender | Single backlog, status tracking, familiar to the team |
| PR communication | GitHub PR comments | Reviewers see questions in context; webhook-driven resume |
| Concurrency | Worker pool (max N concurrent) with priority queue | Multiple PRs active simultaneously, bounded by worker limit |
| Sessions | Persistent per ticket via `claude --resume` | Full conversational memory within a ticket lifecycle |
| Learning | Global journal + per-ticket notes | Cross-ticket learning, self-improvement over time |
| Secrets | `~/.lunar-agent/secrets.env` on the VM | Simple, rotatable, not in repo |
| Observability | Log file + session state files on disk | Check via SSH; web dashboard later |

---

## Components

```
┌──────────────┐     ┌──────────────┐
│   Linear     │     │   GitHub     │
│  (webhooks)  │     │  (webhooks)  │
└──────┬───────┘     └──────┬───────┘
       │                    │
       ▼                    ▼
┌──────────────────────────────────────┐
│         Webhook Server               │
│  POST /webhooks/linear               │
│  POST /webhooks/github               │
│  Validates signatures, parses events │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│          Event Router                │
│  Maps events → tasks                 │
│  Classifies: new_task | pr_comment   │
│    | review | ci_result | ticket_    │
│    update                            │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│          Task Manager                │
│  Priority queue + worker pool (N)    │
│  Park/resume logic                   │
│  Retry budget + circuit breaker      │
└──────┬──────────┬──────────┬─────────┘
       │          │          │
       ▼          ▼          ▼
┌──────────┐┌──────────┐┌──────────┐
│ Worker 1 ││ Worker 2 ││ Worker N │
│ (Claude) ││ (Claude) ││ (Claude) │
└────┬─────┘└────┬─────┘└────┬─────┘
     │           │           │
     ▼           ▼           ▼
┌──────────────────────────────────────┐
│          Session Store               │
│  (JSON files, one per ticket)        │
└──────────────────────────────────────┘
```

---

## Task Lifecycle

### Source: Linear

1. You create a Linear ticket (e.g. "Add Terraform collector") and assign it to the bot's Linear user
2. Linear fires a webhook → server receives it
3. Server creates a new task session, sets status to `starting`
4. Claude reads the ticket description, reads relevant plan from `earthly-agent-config/plans/` if referenced, reads the playbook
5. Claude creates a branch, writes the spec, opens a PR
6. Claude links the PR in the Linear ticket, moves ticket to "In Progress"
7. Task enters `spec_review` phase, gets parked

### Source: GitHub

All subsequent activity on the PR comes via GitHub webhooks:

| GitHub Event | What happens |
|--------------|--------------|
| `issue_comment.created` | Reviewer commented on PR → load session, invoke Claude |
| `pull_request_review.submitted` | Approval or change request → check go-ahead / approval gates |
| `pull_request_review_comment.created` | Inline code comment → load session, invoke Claude |
| `check_suite.completed` | CI finished → if failed, invoke Claude to fix |
| `pull_request.closed` (merged) | PR merged → move Linear ticket to Done, clean up |

### Phase Transitions

```
linear_assigned
  → starting         (Claude picks up ticket, reads context)
  → spec_review      (spec PR opened, waiting for reviewers)
  → implementing     (go-ahead received, Claude writing code)
  → impl_review      (implementation pushed, waiting for approval)
  → merging          (approved, Claude squash-merges + updates cronos)
  → done             (Linear ticket → Done, session archived)

Any phase can transition to:
  → blocked          (Claude posted a question, waiting for answer)
  → error            (retry budget exceeded, needs human attention)
```

---

## Session State

Each task has a JSON file at `~/.lunar-agent/sessions/<ticket-id>.json`:

```json
{
  "ticket_id": "ENG-500",
  "ticket_title": "Add Terraform collector",
  "ticket_url": "https://linear.app/earthly-technologies/issue/ENG-500/...",

  "repo": "earthly/lunar-lib",
  "pr_number": 42,
  "branch": "bender/terraform-collector",

  "phase": "spec_review",
  "status": "parked",

  "go_ahead": {
    "brandon": false,
    "vlad": false,
    "override": null
  },
  "approvals": {
    "brandon": false,
    "vlad": false,
    "override": null
  },

  "blocked": null,

  "last_event_id": "issue_comment:987654321",
  "last_activity_at": "2026-03-12T14:30:00Z",
  "created_at": "2026-03-10T10:00:00Z",

  "conversation_summary": "Spec PR opened. Brandon requested moving .native.terraform paths to .iac category. Fixed in commit abc123. Vlad hasn't reviewed yet.",

  "claude_session_id": "sess_abc123def456",
  "checkpoint_count": 0,
  "last_checkpoint_summary": null,

  "ticket_notes": [
    "Vlad prefers .iac over .infrastructure for the category name"
  ],

  "test_results_posted": false,
  "ci_status": "passing",

  "worktree_path": "/home/bender/repos/lunar-lib-wt-terraform",

  "retry_count": 0,
  "max_retries": 3
}
```

### Blocked state

```json
{
  "blocked": {
    "reason": "Unclear whether nested Terraform modules should be collected recursively",
    "pr_comment_id": 123456789,
    "blocked_since": "2026-03-12T14:30:00Z"
  }
}
```

When a reviewer replies to the blocking comment, the webhook unblocks the task and queues it for resumption.

---

## Worker Pool & Priority Queue

Bender runs up to **N concurrent workers** (configurable, default 3). Each worker handles one task at a time. Each task has its own git worktree and Claude Code session, so there's no filesystem or context contention.

### How it works

1. Events arrive via webhooks and land in a **priority queue**
2. If a free worker exists, it picks up the highest-priority event immediately
3. If all workers are busy, the event waits in the queue
4. When a worker finishes (task parks, blocks, or completes), it picks up the next queued event

### Priority levels

| Priority | Event Type | Rationale |
|----------|-----------|-----------|
| 1 (highest) | CI failure on active task | Fix while context is fresh |
| 2 | Reviewer unblocks a parked task | Resume stalled work |
| 3 | Reviewer comment on active PR | Address feedback |
| 4 | New Linear ticket assigned | Start new work |
| 5 (lowest) | Informational (e.g. CodeRabbit comment) | Handle when idle |

### Preemption

No preemption. If all workers are busy and a priority-1 event arrives, it waits at the front of the queue. Workers finish their current atomic step quickly (commit, push, comment, or park), so the wait is short. Preemption adds complexity with minimal benefit — Claude Code sessions can't be interrupted mid-tool-call cleanly.

### Scaling the worker count

The bottleneck is the Anthropic API rate limit, not the VM. Start with 3 workers — if tasks consistently queue up, increase to 5. Monitor via the status script. Memory usage per Claude Code process is ~200-400 MB, so a `t3.large` (8 GB) handles 5 comfortably.

---

## Persistent Sessions

Each ticket gets a persistent Claude Code session that is resumed across webhook invocations. This preserves full conversational memory — Claude remembers what it tried, what reviewers said, what alternatives were considered, and why decisions were made.

### How it works

1. **New ticket** → start a new Claude Code session. The CLI returns a session ID. Store it in the task JSON.
2. **Subsequent events for that ticket** → resume the session:
   ```bash
   claude --resume <session-id> --dangerously-skip-permissions \
     -m "New event: Vlad commented on PR #42: 'looks good, go ahead'"
   ```
3. Claude picks up with full conversation history — no cold start, no lossy summary.

### Context window exhaustion

Sessions eventually hit the context window limit after many review rounds. When this happens:

1. Bender writes a thorough **checkpoint summary** to the session JSON — what's been done, what's pending, key decisions made, reviewer preferences observed
2. Start a fresh Claude Code session
3. Prime it with: system prompt + playbook + journal + checkpoint summary + recent PR state
4. Save the new session ID to the task JSON

The checkpoint is a graceful degradation, not a failure. Most tickets will complete well within a single session's context window.

### Session storage

Session IDs and Claude Code's internal session data are stored by the CLI itself (typically in `~/.claude/`). The task JSON only stores the session ID for lookup:

```json
{
  "claude_session_id": "sess_abc123def456",
  "checkpoint_count": 0,
  "last_checkpoint_summary": null
}
```

---

## Journal of Learnings

Bender maintains a self-improving knowledge base that grows over time. This is the persistent memory that spans across all tickets and sessions.

### Global journal

File: `~/repos/earthly-agent-config/BENDER-JOURNAL.md`

This file is committed and pushed to the `earthly-agent-config` repo, so it's versioned and reviewable. It's included in the system prompt for every Claude invocation.

Structure:

```markdown
# Bender's Journal

Learnings from past work. I read this at the start of every task.
Last updated: 2026-03-25

## Component JSON
- 2026-03-15: Boolean fields for presence detection are ALWAYS wrong.
  Object presence IS the signal. (Source: Vlad, PR #42)
- 2026-03-18: `.native.<tool>` is ONLY for raw tool output. Normalized
  data at category level. (Source: Brandon, PR #45)

## Collector Code
- 2026-03-20: BusyBox grep on Alpine has no `-P` flag. Use sed.
  CI failed 3 times before I figured this out. (Source: CI, PR #47)

## Policy Code
- 2026-03-22: c.exists() raises NoDataError — use
  c.get_node(path).exists() which returns bool. (Source: crash, PR #48)

## PR Process
- 2026-03-25: When Brandon and Vlad @-mention each other, WAIT.
  Don't jump in. Reverted a commit because of this. (Source: PR #50)

## Reviewer Preferences
- Brandon: Prefers concise PR descriptions. Doesn't like over-explaining.
- Vlad: Reads YAML manifests very carefully. Catches naming inconsistencies.

## Infrastructure / Tooling
- (learnings about earthly, the hub, CI, etc.)
```

### When Bender writes to the journal

- **Reviewer correction:** A reviewer points out a mistake or a better approach → add a learning
- **Repeated failure:** Something fails 2+ times for the same reason → add a learning
- **New pattern discovered:** A workaround or technique that future tasks would benefit from → add a learning
- **Reviewer preference observed:** A reviewer consistently cares about something specific → note it

### How it's written

At the end of each Claude invocation, if Bender learned something new, the executor:
1. Appends the new entry to `BENDER-JOURNAL.md`
2. Commits and pushes to `earthly-agent-config`

This is a lightweight operation — one line appended, one commit. The journal grows organically.

### Per-ticket notes

Stored in the session JSON under `ticket_notes`:

```json
{
  "ticket_notes": [
    "Vlad prefers .iac over .infrastructure for the category name",
    "The pantalasa-cronos/infra component has Terraform files for testing",
    "Tried parsing with hcl2json first but it doesn't handle modules well"
  ]
}
```

These are only loaded when working on that specific ticket. They supplement the persistent session's conversational memory — useful as backup context if a checkpoint is needed.

---

## Claude Invocation

### System prompt (always included)

1. **Identity** — "You are Bender. Bender personality on the outside, Claude precision on the inside. Sign PR comments with Bender-isms."
2. **The playbook** — Full content of `LUNAR-PLUGIN-PLAYBOOK-AI.md`
3. **The journal** — Full content of `BENDER-JOURNAL.md` (grows over time)

### For new sessions (first invocation on a ticket)

4. **The ticket** — Linear ticket title, description, any linked plan
5. **Instructions** — "A new ticket has been assigned to you. Read the description, read the playbook, and begin."

### For resumed sessions

4. **Triggering event** — "Vlad commented on PR #42: 'looks good, go ahead'"
5. **Task state** — Current phase, blocked status (from session JSON)
6. **Instructions** — "Resume your work. The reviewer has responded."

### For checkpointed sessions (new session after context exhaustion)

4. **Checkpoint summary** — The detailed summary from the previous session
5. **Ticket notes** — Per-ticket notes accumulated so far
6. **Current PR state** — Recent comments, CI status, open threads (fetched live)
7. **Triggering event** — Whatever event triggered this invocation
8. **Instructions** — "You're continuing work on this ticket. Your previous session hit the context limit. Read the checkpoint summary for full context."

### Post-invocation

After Claude finishes, the executor:
1. Saves the session ID (if new) or confirms resume succeeded
2. Updates the session JSON (phase, status, ticket notes, conversation summary)
3. Checks if Bender wrote any journal entries → commit and push if so
4. Checks if the task is parked, blocked, or needs further action
5. Logs the invocation to `~/.lunar-agent/logs/`

---

## GitHub App

### Setup

- Register a GitHub App under the `earthly` org (or Brandon's account)
- Name: `bender-earthly`
- Webhook URL: `https://<vm-ip-or-domain>/webhooks/github`
- Webhook secret: random string, stored in secrets.env
- Homepage URL: optional (can point to the repo)

### Permissions needed

| Permission | Access | Why |
|-----------|--------|-----|
| Contents | Read & Write | Clone repos, push branches, read files |
| Pull requests | Read & Write | Create PRs, comment, merge |
| Issues | Read & Write | Read issue comments (PRs use issue comment events) |
| Checks | Read | Monitor CI status |
| Metadata | Read | Required for app installation |

### Events to subscribe to

- `issue_comment`
- `pull_request_review`
- `pull_request_review_comment`
- `check_suite`
- `pull_request`

### Installation

Install the App on:
- `earthly/lunar-lib`
- `earthly/lunar` (if the bot works on core too)
- `pantalasa-cronos/*` (all repos in the org, for testing)

### Authentication

The App generates short-lived installation tokens. The webhook server:
1. Receives event with `installation.id`
2. Creates a JWT signed with the App's private key
3. Exchanges JWT for an installation access token (valid 1 hour)
4. Uses the token for `gh` and API calls during that invocation

Store the App's private key at `~/.lunar-agent/github-app-private-key.pem`.

---

## Linear Integration

### Setup

- Create a Linear user for the bot named "Bender"
- Create a Linear API token for that user, stored in secrets.env
- Configure Linear webhook:
  - URL: `https://<vm-ip-or-domain>/webhooks/linear`
  - Events: Issue updates (specifically: assignee changes, status changes, comments)

### Events to handle

| Event | Action |
|-------|--------|
| Issue assigned to bot | Create new task session, start working |
| Issue unassigned from bot | Cancel the task (if not already merged) |
| Issue comment (from human) | Forward context to Claude if task is blocked |
| Issue status changed to "Cancelled" | Cancel the task, close PR if open |

### Ticket → task mapping

The session store maps `ticket_id` → session file. When a Linear event arrives, look up the session by ticket ID. When a GitHub event arrives, look up the session by PR number.

Index files for fast lookup:
- `~/.lunar-agent/index/by-ticket/<ticket-id>` → symlink to session file
- `~/.lunar-agent/index/by-pr/<repo>/<pr-number>` → symlink to session file

### Status sync

| Agent phase | Linear status |
|-------------|--------------|
| starting | In Progress |
| spec_review | In Review |
| implementing | In Progress |
| impl_review | In Review |
| blocked | Blocked (custom status, or add a "Blocked" label) |
| merging | In Progress |
| done | Done |
| error | Blocked |

---

## VM Setup

### Machine

- **Instance type:** `t3.large` or `t3.xlarge` (4-8 vCPU, 8-16 GB RAM). Each Claude Code worker uses ~200-400 MB; with 3-5 concurrent workers plus `earthly` builds, 8 GB is the minimum.
- **Storage:** 50-100 GB EBS (repos, worktrees, Docker images for earthly)
- **OS:** Ubuntu 22.04 or Amazon Linux 2023
- **Elastic IP:** Stable IP for webhook URLs (or use a domain)

### Software to install

- `git`
- `gh` (GitHub CLI)
- `jq`
- `curl`
- `node` (v20+) — for the webhook server
- `claude` (Claude Code CLI)
- `earthly`
- `docker` (required by earthly)
- `lunar` CLI (built from source)

### Directory structure

```
/home/bender/
├── .lunar-agent/
│   ├── secrets.env              # All secrets (sourced by the server)
│   ├── github-app-private-key.pem
│   ├── config.json              # Runtime config (model, workers, limits)
│   ├── sessions/                # One JSON file per task
│   │   ├── ENG-500.json
│   │   └── ENG-501.json
│   ├── index/                   # Lookup indexes
│   │   ├── by-ticket/
│   │   └── by-pr/
│   ├── logs/                    # Invocation logs
│   │   ├── server.log           # Webhook server log
│   │   ├── 2026-03-12-ENG-500-001.log  # Claude invocation logs
│   │   └── 2026-03-12-ENG-500-002.log
│   └── archive/                 # Completed sessions
├── repos/
│   ├── lunar-lib/               # Main checkout
│   ├── lunar-lib-wt-terraform/  # Worktree per task
│   ├── lunar/                   # Core platform
│   ├── pantalasa-cronos/
│   │   └── lunar/
│   └── earthly-agent-config/    # This repo (includes BENDER-JOURNAL.md)
└── server/                      # The webhook server code
    ├── package.json
    ├── src/
    │   ├── index.ts             # Entry point, HTTP server
    │   ├── webhooks/
    │   │   ├── github.ts        # GitHub event parsing + validation
    │   │   └── linear.ts        # Linear event parsing + validation
    │   ├── router.ts            # Event → task routing
    │   ├── task-manager.ts      # Worker pool, priority queue, park/resume
    │   ├── session-store.ts     # Read/write session JSON
    │   ├── claude-executor.ts   # Invoke Claude Code CLI
    │   ├── context-builder.ts   # Assemble prompt from playbook + session + event
    │   └── github-auth.ts       # App JWT + installation token management
    └── tsconfig.json
```

### Secrets file

`~/.lunar-agent/secrets.env`:

```bash
# GitHub App
GITHUB_APP_ID=123456
GITHUB_APP_PRIVATE_KEY_PATH=/home/bender/.lunar-agent/github-app-private-key.pem
GITHUB_WEBHOOK_SECRET=<random string>

# Linear
LINEAR_API_TOKEN=lin_api_...
LINEAR_WEBHOOK_SECRET=<from Linear settings>
LINEAR_BOT_USER_ID=<Bender's Linear user ID>

# Lunar
LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643

# Anthropic
ANTHROPIC_API_KEY=sk-ant-...
```

### Config file

`~/.lunar-agent/config.json` — runtime settings that don't contain secrets. Edit and restart the server (or hot-reload if supported). When new models come out, just change `claude.model` here.

```json
{
  "claude": {
    "model": "claude-sonnet-4-20250514",
    "max_turns": 50
  },
  "workers": {
    "max_concurrent": 3
  },
  "circuit_breaker": {
    "max_duration_minutes": 30,
    "max_tokens": 100000
  },
  "retry": {
    "max_retries": 3
  }
}
```

| Field | What it does | When to change |
|-------|-------------|----------------|
| `claude.model` | Model passed to `claude --model` | New model release (e.g. `claude-opus-4-20250514`) |
| `claude.max_turns` | Max tool-call turns per invocation | If tasks are hitting the limit prematurely |
| `workers.max_concurrent` | Worker pool size | Scale up if tasks queue; scale down to reduce API cost |
| `circuit_breaker.max_duration_minutes` | Kill invocation after N minutes | Implementation phases may need more; review responses less |
| `circuit_breaker.max_tokens` | Kill invocation after N tokens | Cost control |
| `retry.max_retries` | Times to retry a failing step before marking `error` | Lower = faster escalation to human |

---

## Observability (v1)

### Log file

The server writes structured JSON logs to `~/.lunar-agent/logs/server.log`:

```json
{"ts": "2026-03-12T14:30:00Z", "level": "info", "event": "webhook_received", "source": "github", "type": "issue_comment", "pr": 42, "repo": "earthly/lunar-lib"}
{"ts": "2026-03-12T14:30:01Z", "level": "info", "event": "task_resumed", "ticket": "ENG-500", "phase": "spec_review", "trigger": "reviewer_comment"}
{"ts": "2026-03-12T14:35:00Z", "level": "info", "event": "claude_invocation_complete", "ticket": "ENG-500", "duration_ms": 287000, "tokens_used": 45000}
{"ts": "2026-03-12T14:35:01Z", "level": "info", "event": "task_parked", "ticket": "ENG-500", "phase": "spec_review", "reason": "waiting_for_reviewer"}
```

### CLI status check

A small script `status.sh` that reads session files and prints a table:

```
$ ./status.sh

Lunar Agent Status — 2026-03-12 14:35 UTC
Workers: 2/3 active

ACTIVE TASKS:
  Ticket     Phase          Status   PR    Worker  Last Activity
  ENG-501    implementing   active   #45   W1      now (running tests)
  ENG-503    spec_review    active   #49   W2      now (writing README)
  ENG-500    spec_review    parked   #42   —       2h ago (waiting for Vlad)
  ENG-502    blocked        blocked  #47   —       1d ago (Q: nested module handling)

COMPLETED (last 7 days):
  ENG-498    done           merged   #40   3d ago
  ENG-499    done           merged   #41   2d ago

QUEUE:
  1 event pending (priority 5: CodeRabbit comment on #45)
```

### Per-invocation logs

Each Claude invocation is logged to a separate file with the full prompt and response, so you can debug what Claude saw and did:

`~/.lunar-agent/logs/2026-03-12-ENG-500-003.log`

---

## Error Handling

### Retry budget

Each task has a `retry_count` and `max_retries` (default 3). If Claude fails on the same step (e.g. CI keeps failing after its fix attempts), increment the counter. When exhausted:

1. Set task status to `error`
2. Post a comment on the PR (in Bender voice): "Look, I've tried fixing this 3 times and it's still broken. Even I have limits. Somebody help me out here. Error: [description] 🤖"
3. Update Linear ticket status to Blocked
4. Log the error

### Circuit breaker

If a single Claude invocation exceeds 15 minutes or 100k tokens, kill it and log a warning. This prevents runaway sessions.

### Webhook replay

If the server is down when a webhook fires, GitHub retries (with backoff) for up to a few hours. Linear also retries. For longer outages, the server should do a "catch-up" on startup: scan all active sessions, check their PRs for new comments/events since `last_event_id`, and queue any missed events.

---

## Security Boundaries

The VM is the security perimeter:

- Only repos the GitHub App is installed on are accessible
- The `LUNAR_HUB_TOKEN` is scoped to the cronos demo environment
- The `LINEAR_API_TOKEN` is scoped to the bot's user permissions
- The `ANTHROPIC_API_KEY` is the only high-value secret — rate-limit it at the Anthropic dashboard
- SSH access to the VM is restricted to Brandon (key-based auth, no password login)
- The webhook endpoints validate signatures before processing any event
- No inbound ports except 443 (HTTPS for webhooks) and 22 (SSH)

---

## Future Enhancements

Things explicitly deferred to v2+:

- **Slack notifications** — escalation channel for blocked tasks, daily digest
- **Web dashboard** — real-time view of task status, queue, logs, journal
- **Dynamic worker scaling** — auto-scale worker count based on queue depth and API rate limits
- **Auto-assign tickets** — Bender picks up unassigned tickets from a "Bot Queue" label/project
- **Cost tracking** — log token usage per task, per ticket, per day
- **MCP browser** — Playwright MCP server for testing web UIs, checking Grafana dashboards
- **Journal review** — periodic review of journal entries with Brandon to prune outdated learnings
- **Bender avatar** — custom profile picture for the GitHub and Linear accounts
