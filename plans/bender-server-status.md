# Bender Server — Current Status (2026-03-26)

## What's Working

- **Linear → Bender pipeline**: Assign ticket to Bender in Linear → AgentSessionEvent webhook → session created → Claude Code CLI runs → code written → branch pushed → PR opened
- **GitHub → Bender pipeline**: PR comments/reviews trigger webhooks → session matched by PR number → Claude responds and pushes fixes
- **Linear chat (fast path)**: Messages in Linear agent thread → direct Sonnet API call (~3-5s) → Bender replies in character
- **Bender personality**: AI-generated status messages via Haiku, full Bender identity in Claude prompts
- **`bender-say` script**: Available for Claude to post mid-run updates to Linear
- **PR review replies**: Inline review comments pass `in_reply_to` comment ID so Claude replies in-thread
- **Worker pool**: 3 concurrent workers, duplicate ticket prevention, self-comment loop prevention
- **GitHub App auth**: Installation tokens generated per invocation for git/gh operations

## Known Issues for Next Session

1. **Claude session resume** — `claude_session_id` never gets captured from CLI output. Each invocation starts fresh. Need to parse the session ID from Claude's stderr.
2. **Session phase stuck at `starting`** — Router never advances phase. Need to detect PR creation (move to `spec_review`), go-ahead comments (move to `implementing`), etc.
3. **`bender-say` not used by Claude** — Claude prints to stdout instead of calling `bender-say`. May need stronger prompt instructions or to make it an MCP tool.
4. **Journal not on VM** — `~/repos/earthly-agent-config` not cloned. Journal loads as "(no journal yet)".
5. **Debug logging still in index.ts** — The prompted payload dump should be removed or made conditional.
6. **Self-improvement** — Bender should be able to edit `~/bender/server/src/`, rebuild, and restart himself. Needs `CLAUDE.md` in bender repo + prompt instructions.
7. **Linear status sync** — Session phase changes don't update the Linear ticket status (In Progress, In Review, etc.)

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
- `max_turns: 200` (50 was too few — Claude used all turns writing code, couldn't push)
- Git credential helper on VM uses `$GH_TOKEN` env var (set from GitHub App installation token per invocation)
- Fast Haiku path for Linear chat (direct API call, no CLI spawn)
- Claude's stdout posted directly to Linear as response (no re-Benderizing — already in character)

## Linear Tickets Created

- **ENG-478**: Phase 1 parent (12 sub-tasks for Starter tier)
- **ENG-491**: Phase 2 parent (10 sub-tasks for Starter+ tier)
- **ENG-486**: .NET/C# collector + policy (test ticket, PR #94 open)
