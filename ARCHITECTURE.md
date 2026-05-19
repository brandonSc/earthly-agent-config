# Bender Architecture

Bender is an autonomous coding agent for the Lunar platform. He receives work via Linear tickets, GitHub PR events, and Slack messages, then uses Claude Code CLI to write code, open PRs, respond to reviews, and test on live environments.

## System overview

```
  ┌──────────┐    ┌──────────┐    ┌──────────┐
  │  Linear  │    │  Slack   │    │  GitHub  │
  │ tickets  │    │ messages │    │ webhooks │
  └────┬─────┘    └────┬─────┘    └────┬─────┘
       │               │               │
       └───────┬───────┴───────┬───────┘
               │               │
        ┌──────▼──────┐        │
        │   Express   │◄───────┘
        │ (port 3000) │
        └──────┬──────┘
               │
       ┌───────▼────────┐
       │  Task Manager  │
       └──┬──────────┬──┘
          │          │
          │     Linear / GitHub events
          │          │
   Slack  │    ┌─────▼────────┐
   events │    │    Router    │── Match to session, phase transitions
          │    └─────┬────────┘
   ┌──────▼──────┐   │
   │   Sonnet    │   │
   │ Classifier  │   │
   │(inline API) │   │
   └──┬──┬──┬────┘   │
      │  │  │        │
 ◄────┘  │  │  ┌─────▼────────┐
 plan    │  └─►│ Opus Worker  │── Background, long-running
 ◄───────┘work │ (CLI spawn)  │
 chat          └─────┬────────┘
                     │
(back to          ┌──▼───────────┐
 Slack)           │  Claude Code │── Full tool access:
                  │     CLI      │   files, bash, git,
                  └──────────────┘   gh, web fetch
```

## How events flow

1. **Webhook arrives** -- Express server receives GitHub, Linear, or Slack events via HTTP endpoints in `index.ts`. Signatures are verified per-platform.

2. **Event is parsed** -- Platform-specific parsers (`webhooks/github.ts`, `webhooks/linear.ts`, `webhooks/slack.ts`) normalize the raw payload into a `TaskEvent` with a type, priority, source, and metadata.

3. **Event is routed** -- `router.ts` matches the event to an existing session (by ticket ID, PR number, or Slack thread). It determines the action: create a new session, invoke Claude on an existing one, or skip. It also manages phase transitions (spec_review -> implementing -> impl_review -> merging -> done).

4. **Event is dispatched** -- `task-manager.ts` queues the event, applies debounce for rapid-fire comments, and assigns it to a free worker slot when one is available.

5. **Claude is invoked** -- `claude-executor.ts` spawns the Claude Code CLI (`claude -p`) with a prompt built by `context-builder.ts`. The prompt includes identity, playbook, journal, phase-specific instructions, and event details.

6. **Results are processed** -- When Claude exits, the task manager extracts PR numbers from the output, updates session state, and posts status to Slack.

## Two execution paths

### Sonnet chat (fast, inline)

For Slack messages and Linear chat, the task manager calls the Anthropic API directly with Sonnet. This runs inline (not spawned), returns in 1-3 seconds, and handles quick responses, plan proposals, and action classification. No tool access -- just text in, text out.

### Opus worker (full, background)

For real work (new tickets, PR reviews, Slack work requests), the task manager spawns Claude Code CLI as a background process with Opus and `--effort max`. The worker has full tool access: file read/write, bash, git, gh CLI, web fetch. Workers run for minutes to hours and communicate results via Slack.

## Session lifecycle

Sessions track the state of a task from creation to completion.

```
starting ──► spec_review ──► implementing ──► impl_review ──► merging ──► done
                                                                │
                                                          (blocked if test
                                                           results not posted)
```

- **starting** -- New ticket picked up, Claude reads docs and creates spec
- **spec_review** -- Spec PR open, primary reviewer iterating
- **implementing** -- Secondary reviewer approved spec, Claude writing code and testing
- **impl_review** -- Implementation pushed, waiting for both reviewers to approve
- **merging** -- Both approvals received, pre-merge checklist
- **done** -- Merged, cleaned up, Linear ticket closed

Sessions are JSON files in `~/.bender/sessions/`. Each maps a ticket to its PR, Slack thread, Claude session ID, approvals, and phase.

## Key source files

| File | Lines | Purpose |
|------|-------|---------|
| `task-manager.ts` | 1527 | Worker pool, Slack handler, Sonnet classifier, work dispatch |
| `index.ts` | 597 | Express server, webhook endpoints, health/status API |
| `context-builder.ts` | 438 | Builds prompts for new/resumed/checkpointed sessions, phase-specific instructions |
| `claude-executor.ts` | 386 | Spawns Claude Code CLI, captures session IDs, streams output to log files |
| `session-store.ts` | 363 | Session CRUD, PR matching, thread linking, archiving |
| `router.ts` | 298 | Event-to-session matching, phase transitions, approval tracking |
| `slack-evaluator.ts` | 187 | Lurk mode -- Haiku evaluates channel messages to decide if Bender should chime in |
| `types.ts` | 172 | Session, TaskEvent, Config, Worker interfaces |
| `linear-client.ts` | 169 | Linear GraphQL API (issues, states, close tickets) |
| `worker-tracker.ts` | 152 | Track background Claude processes, log tailing, cancellation |
| `linear-auth.ts` | 154 | Linear OAuth with refresh token |
| `slack-plans.ts` | 124 | Store pending plans for plan-first workflow |
| `slack-client.ts` | 119 | Slack Web API wrapper (postMessage, addReaction, getThreadMessages) |
| `slack-threads.ts` | 96 | Track active threads with 24h TTL |
| `config.ts` | 80 | Load config.json + secrets.env |
| `slack-memory.ts` | 78 | Per-user/per-channel conversation persistence |
| `github-auth.ts` | 68 | GitHub App JWT auth, installation tokens per org |

## Slack integration

Bender handles Slack through a single Sonnet classifier call that returns a JSON action:

- **chat** -- Answer directly (fast, no tools)
- **work** -- Dispatch a background Opus worker (full tool access)
- **plan** -- Propose numbered steps, wait for approval
- **status** -- Report on running worker activity
- **cancel/redirect** -- Stop or change direction of active work
- **pass** -- Stay silent (message not directed at Bender)
- **react_only** -- Acknowledge with an emoji reaction
- **dismiss** -- Leave the thread

When a worker is running in a thread, most messages are routed to the worker by default (not answered by Sonnet chat).

## Guardrails

### Claude Code hooks (`~/.claude/settings.json`)

PostToolUse hooks fire after every file edit, running `.lunar/checks.yml` from the repo. These catch SVG fill errors, GNU grep extensions, lint failures, and surface nudge reminders. PreToolUse hooks validate `lunar` CLI execution context.

### Git pre-commit hooks

Hard gates on each repo that block commits containing SVG white fills, temporary image tags, branch refs in config, or sensitive keywords.

### Phase-aware prompting

`context-builder.ts` injects phase-specific checklists into every prompt. The `implementing` phase includes a 14-step cronos testing checklist. The `merging` phase includes a pre-merge checklist. Phase transition notes explain why the agent is in its current phase.

### Test results gate

`router.ts` blocks the transition from `impl_review` to `merging` if `test_results_posted` is false.

## Configuration (hot-reloaded)

These files are read fresh on every Claude invocation -- no restart needed:

| File | Purpose |
|------|---------|
| `~/repos/CLAUDE.md` | Operational rules (commit discipline, review handling, communication) |
| `~/repos/BENDER-IDENTITY.md` | Personality and voice guidelines |
| `~/repos/BENDER-JOURNAL.md` | Learnings from past work (Bender appends to this) |
| `~/repos/PEOPLE.json` | Team member name -> GitHub/Slack/Linear ID mapping |
| `~/bender/worker-context.md` | Operational notes for workers (hub sync, testing workflow, hooks) |
| `~/.claude/settings.json` | Claude Code hook configuration |

## Infrastructure

- **EC2 instance** on AWS (us-west-2), managed by systemd (`bender.service`)
- **GitHub App** with 4 installations (brandonSc, earthly, pantalasa, pantalasa-cronos)
- **Secrets** in `~/.bender/secrets.env` (GitHub, Linear, Slack, Anthropic keys)
- Deploy: `git pull && npm run build && sudo systemctl restart bender`
- Safe restart: check for running workers first, use `pending-restart.json` if workers are active
