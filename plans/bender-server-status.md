# Bender Server — Current Status (2026-03-30)

## What's Working

- **Linear → Bender pipeline**: Assign ticket to Bender in Linear → AgentSessionEvent webhook → session created → Claude Code CLI runs → code written → branch pushed → PR opened
- **GitHub → Bender pipeline**: PR comments/reviews trigger webhooks → session matched by PR number → Claude responds and pushes fixes
- **Linear chat (fast path)**: Messages in Linear agent thread → direct Sonnet API call (~3-5s) → Bender replies in character
- **Bender personality**: AI-generated status messages via Haiku, identity loaded from external `BENDER-IDENTITY.md` (editable without redeploy)
- **`bender-say` script**: Available for Claude to post mid-run updates to Linear
- **PR review replies**: Inline review comments pass `in_reply_to` comment ID so Claude replies in-thread
- **Worker pool**: 3 concurrent workers, events queued when ticket is busy (not dropped)
- **Self-comment loop prevention**: Checks user.id, user.name, and actorId
- **GitHub App auth**: Installation tokens generated per invocation for git/gh operations
- **Commit avatar**: Commits show as `me-bender[bot]` with the GitHub App avatar
- **Linear token auto-refresh**: Refresh token stored, auto-refreshes on 401
- **Re-assignment awareness**: Reuses existing session, tells Claude "you already have PR #X open"
- **Model**: Claude Opus 4.6 with `--effort max` (extended thinking)
- **CLAUDE.md**: Operational rules loaded from `~/repos/CLAUDE.md` — read docs first, always commit, verify all threads, CI checks
- **BENDER-JOURNAL.md**: Learning journal at `~/repos/BENDER-JOURNAL.md` — Bender writes learnings after PR merges

## Known Issues for Next Session

1. **Claude session resume** — `claude_session_id` never gets captured from CLI output. Each invocation starts fresh.
2. **Session phase stuck at `starting`** — Router never advances phase. Need to detect PR creation → `spec_review`, go-ahead → `implementing`, etc.
3. **Self-improvement** — Bender should be able to edit his own server code, rebuild, and restart. Needs instructions.
4. **Linear status sync** — Session phase changes don't update the Linear ticket status.
5. **Debug logging in index.ts** — Prompted payload dump should be removed or made conditional.
6. **Redundant runs** — When multiple comments queue up, Claude runs for each even if earlier run addressed everything. Could add a "check if all threads resolved, exit early if so" step.

## Architecture

- **Repo**: `brandonSc/bender` (GitHub redirects from `earthly/bender`)
- **VM**: `ip-172-31-6-125.us-west-2.compute.internal` (SSH via `~/.ssh/lunar-demo.pem`)
- **Systemd service**: `bender.service` — `node dist/index.js` in `/home/ubuntu/bender/server`
- **Deploy**: `cd ~/bender/server && git pull && npm run build && sudo systemctl restart bender`
- **Secrets**: `~/.bender/secrets.env`
- **Sessions**: `~/.bender/sessions/<ticket-id>.json`
- **Logs**: `~/.bender/logs/`

## Key Decisions Made During Setup

- Linear native Agent system (`actor=app`, `app:assignable`, `app:mentionable`) — no billable seat
- Separate webhook signing secrets: workspace webhook (`LINEAR_WEBHOOK_SECRET`) vs OAuth app webhook (`LINEAR_APP_WEBHOOK_SECRET`)
- `AgentSessionEvent` webhooks for assignments (not `Issue` webhooks — those don't fire for agent users)
- User messages in prompted events at `agentActivity.content.body` (not `agentActivity.body`)
- `max_turns: 0` (unlimited — circuit breaker is the safety valve)
- Model: `claude-opus-4-6` with `--effort max`
- Git credential helper on VM uses `$GH_TOKEN` env var (set from GitHub App installation token per invocation)
- Git identity: `me-bender[bot]` / `267701604+me-bender[bot]@users.noreply.github.com`
- Fast Sonnet path for Linear chat (direct API call, no CLI spawn)
- Claude's stdout posted directly to Linear as response (no re-Benderizing — already in character)
- External config files (editable without redeploy): `~/repos/BENDER-IDENTITY.md`, `~/repos/CLAUDE.md`, `~/repos/BENDER-JOURNAL.md`
- CWD set to `~/repos/lunar-lib` when it exists, so Claude sees repo docs automatically

## Editable Files on VM (no redeploy needed)

| File | Purpose | Location |
|------|---------|----------|
| `BENDER-IDENTITY.md` | Personality, voice, catchphrase rules | `~/repos/BENDER-IDENTITY.md` |
| `CLAUDE.md` | Operational rules (commit, CI, docs, cleanup) | `~/repos/CLAUDE.md` + `~/repos/lunar-lib/CLAUDE.md` |
| `BENDER-JOURNAL.md` | Learning journal (Bender writes to this) | `~/repos/BENDER-JOURNAL.md` |

## Linear Tickets Created

- **ENG-478**: Phase 1 parent (12 sub-tasks for Starter tier)
- **ENG-491**: Phase 2 parent (10 sub-tasks for Starter+ tier)
- **ENG-486**: .NET/C# collector + policy (test ticket, PR #94 open)
