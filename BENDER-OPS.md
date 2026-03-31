# Bender Operations Guide

Quick reference for agents working on or debugging the Bender autonomous agent server.

## SSH Access

```bash
ssh -i ~/.ssh/lunar-demo.pem ubuntu@ip-172-31-6-125.us-west-2.compute.internal
```

## Service Management

```bash
# Check status
systemctl is-active bender

# View logs (live)
sudo journalctl -u bender -f

# View recent logs
sudo journalctl -u bender --since "5 min ago" --no-pager

# Restart (kills any running Claude processes)
sudo systemctl restart bender

# Health check
curl -s localhost:3000/health
curl -s localhost:3000/status | jq .
```

## Deploy Changes

```bash
cd ~/bender/server
git pull
npm run build
sudo systemctl restart bender
```

**IMPORTANT:** Check if workers are busy before restarting:
```bash
curl -s localhost:3000/status | jq '.workers[] | select(.busy)'
```

## Key Directories on VM

| Path | Purpose |
|------|---------|
| `~/bender/` | Bender server source (git repo: brandonSc/bender) |
| `~/bender/server/src/` | TypeScript source files |
| `~/bender/server/dist/` | Compiled JS (after `npm run build`) |
| `~/repos/` | Working directory for Claude CLI |
| `~/repos/lunar-lib/` | Cloned lunar-lib repo |
| `~/repos/CLAUDE.md` | Operational rules (editable, no redeploy needed) |
| `~/repos/BENDER-IDENTITY.md` | Personality config (editable, no redeploy needed) |
| `~/repos/BENDER-JOURNAL.md` | Learning journal (Bender writes to this) |
| `~/repos/PEOPLE.json` | Team member mapping (Linear → Slack → GitHub) |
| `~/repos/meeting-notes/` | Meeting transcripts for context |
| `~/.bender/secrets.env` | All secrets (GitHub, Linear, Slack, Anthropic) |
| `~/.bender/sessions/` | Active session JSON files (one per task) |
| `~/.bender/archive/` | Completed/closed sessions |
| `~/.bender/logs/` | Claude invocation logs (streaming tool calls) |
| `~/.bender/slack-memory/` | Per-user and per-channel Slack conversation logs |
| `~/.bender/grafana-credentials` | Grafana auth for screenshots |
| `~/.bender/linear-token.json` | Linear OAuth token (auto-refreshes) |
| `~/.bender/github-app-key.pem` | GitHub App private key |

## Editable Config Files (no restart needed)

These are read fresh every Claude invocation:

| File | What it controls |
|------|-----------------|
| `~/repos/CLAUDE.md` | Operational rules: plan-first, always commit, check CI, etc. |
| `~/repos/BENDER-IDENTITY.md` | Personality: voice, catchphrases, dos/don'ts |
| `~/repos/BENDER-JOURNAL.md` | Learnings from past work (Bender appends to this) |
| `~/repos/PEOPLE.json` | Name → GitHub/Slack/Linear ID mapping |

Also copy to `~/repos/lunar-lib/CLAUDE.md` if updating CLAUDE.md (Claude CLI reads from CWD).

## Architecture Overview

```
Webhooks → Express server (port 3000) → Event Router → Task Manager → Claude Code CLI
                                                              ↓
                                              Slack (Sonnet chat / Opus work)
                                              Linear (AgentSession activities)
                                              GitHub (PR comments, pushes)
```

### Key Source Files

| File | Purpose |
|------|---------|
| `index.ts` | Express server, webhook endpoints, Slack/Linear/GitHub routing |
| `task-manager.ts` | Worker pool, debounce, plan-first workflow, Slack handler, CLI dispatch |
| `claude-executor.ts` | Spawns Claude Code CLI, stream-json parsing, session ID capture |
| `context-builder.ts` | Builds prompts for new/resumed/checkpointed sessions |
| `router.ts` | Maps events to sessions, phase transitions, auto-close tickets on merge |
| `session-store.ts` | JSON file CRUD, PR matching (primary + additional_prs), fallback linking |
| `types.ts` | Session, TaskEvent, Config, Worker interfaces |
| `webhooks/github.ts` | GitHub event parsing, signature verification |
| `webhooks/linear.ts` | Linear event parsing, AgentSessionEvent handling, dedup |
| `webhooks/slack.ts` | Slack event parsing, file upload support |
| `slack-client.ts` | Slack Web API wrapper (postMessage, addReaction, etc.) |
| `slack-memory.ts` | Per-user/per-channel conversation persistence |
| `slack-plans.ts` | Pending plan storage for plan-first workflow |
| `slack-threads.ts` | Thread tracking (24hr timeout) |
| `slack-evaluator.ts` | Lurk mode: Haiku evaluates whether to chime in |
| `linear-agent.ts` | Linear AgentActivity emissions (thought/response/error) |
| `linear-auth.ts` | Linear OAuth with refresh token |
| `linear-client.ts` | Linear GraphQL API (issues, states, close tickets) |
| `github-auth.ts` | GitHub App JWT auth, installation tokens |
| `config.ts` | Load config.json + secrets.env |

## Model Selection

| Event type | Model | Effort | Resume |
|------------|-------|--------|--------|
| New ticket (Linear) | Opus 4.6 | max | New session |
| PR review comment (GitHub) | Opus 4.6 | max | Yes (--resume) |
| CI failure | Opus 4.6 | max | Yes |
| Linear chat (agent_prompt) | Sonnet | default | No (fresh) |
| Slack chat | Sonnet | default | No (stateless API) |
| Slack work request | Opus 4.6 | max | No (fresh + session context) |
| Status messages (benderSpeak) | Haiku | — | — |
| Lurk evaluator | Haiku | — | — |

## GitHub App Installations

The app has 4 installations. Token selection is by repo org:

| Org | Installation ID | Key repos |
|-----|----------------|-----------|
| brandonSc | 120369246 | bender |
| earthly | 120185203 | lunar, lunar-lib, skills-internal |
| pantalasa | 120180295 | lunar, backend, dotnet-service, etc. |
| pantalasa-cronos | 120179940 | lunar, backend, frontend, auth, etc. |

## Session Management

Sessions are JSON files in `~/.bender/sessions/`. Each maps a task to its PR, Slack thread, and Claude session.

```bash
# View all active sessions
for f in ~/.bender/sessions/*.json; do
  python3 -c "import json; s=json.load(open('$f')); print(f\"{s['ticket_id']}: PR#{s['pr_number']} {s['repo']} thread={s.get('slack_thread_ts','none')}\")"
done

# Manually fix a session
python3 -c "
import json
with open('$HOME/.bender/sessions/slack-pr-1224.json') as f:
    s = json.load(f)
s['pr_number'] = 1224
s['repo'] = 'earthly/lunar'
s['slack_thread_ts'] = '1774974736.289769'
with open('$HOME/.bender/sessions/slack-pr-1224.json', 'w') as f:
    json.dump(s, f, indent=2)
"

# Archive a completed session
mv ~/.bender/sessions/ENG-486.json ~/.bender/archive/
```

## Debugging Common Issues

### Bender not responding to PR comments
1. Check webhooks arriving: `sudo journalctl -u bender --since "5 min ago" | grep github`
2. Check session matching: look for "skip — no matching session"
3. Check if PR is tracked: `grep pr_number ~/.bender/sessions/*.json`
4. If not tracked, create a session or let fallback link it

### Bender working on wrong PR
- Check which session the event matched to
- The `FOCUS` instruction in the prompt should prevent wandering
- If GitHub API returns 404, check the installation token org matching

### Double replies
- Slack: dedup by message `ts` (30s window)
- Linear: `AgentSessionEvent` + `Comment/create` dedup (5s window)
- Server no longer posts completion summaries — Claude handles its own communication

### Stale context / hallucinated rules
- Linear chat and Slack work use fresh invocations (no --resume)
- Only GitHub PR events use --resume for continuity
- If Claude references rules that don't exist, check for stale session with old conversation

### Token / permission errors
- GitHub 404 → wrong installation token (check org matching in getGitHubToken)
- Linear 401 → token expired (should auto-refresh, check linear-token.json)
- Slack 403 on file download → need files:read scope

## Slack Integration

- **DMs:** always respond (full Sonnet)
- **@mentions in channels:** always respond, track thread for 24hrs
- **Thread follow-ups:** respond without needing @mention if thread is tracked
- **Lurk mode:** Haiku evaluates each channel message — ignore/emoji/reply
- **Work requests:** Sonnet classifies chat/plan/work → plan-first for non-trivial
- **File uploads:** file_share events parsed, download URLs passed to Claude
- **Memory:** per-user conversation history persists across channels

## Plan-First Workflow

Non-trivial work gets a plan before execution:
1. Sonnet classifies message as "plan" → posts numbered steps + "Go ahead?"
2. Plan stored in memory, thread tracked
3. User approves → dispatches Opus CLI to do the work
4. Dead-simple tasks skip planning, execute immediately

## Linear Integration

- `AgentSessionEvent/created` → new ticket pickup
- `AgentSessionEvent/prompted` → user message in Linear thread
- On new ticket: DM the assignee on Slack (via PEOPLE.json lookup) to create "agent tab" thread
- On PR merge: auto-close Linear ticket + archive session
- Token auto-refreshes via stored refresh_token

## Secrets Reference

All in `~/.bender/secrets.env`:
```
GITHUB_APP_ID=3075428
GITHUB_APP_PRIVATE_KEY_PATH=/home/ubuntu/.bender/github-app-key.pem
GITHUB_WEBHOOK_SECRET=<secret>
LINEAR_CLIENT_ID=4ec656a74e5675ffb357d2d9ade01f65
LINEAR_CLIENT_SECRET=<secret>
LINEAR_WEBHOOK_SECRET=<workspace webhook secret>
LINEAR_APP_WEBHOOK_SECRET=<oauth app webhook secret>
LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643
ANTHROPIC_API_KEY=<key>
SLACK_BOT_TOKEN=xoxb-<token>
SLACK_SIGNING_SECRET=<secret>
```
