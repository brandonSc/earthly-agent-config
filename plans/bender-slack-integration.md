# Bender Slack Integration — Design Plan

## Overview

Bender joins Slack channels as a team member. Three modes:

1. **Direct request** (`@Bender`) — always responds, full Claude invocation
2. **Lurk mode** (configurable) — reads everything, occasionally chimes in with quips, emoji reactions, or genuinely helpful observations
3. **Awareness bridge** — Slack ↔ Linear ↔ GitHub, can create tickets and start work from Slack

## Threading Rules

**Match the vibe.** Don't force threading conventions:

- If people are chatting top-level and Bender wants to quip → top-level, like everyone else
- If someone says "@Bender work on this" → reply in thread (keep channel clean)
- If there's an existing thread discussion → reply in thread
- If doing a proactive status update ("PR #94 merged") → top-level is fine
- General rule: observe how the conversation is flowing and match that

## Architecture

### New files in bender server

```
server/src/
├── webhooks/slack.ts        — Slack Events API parsing, signature verification
├── slack-evaluator.ts       — Haiku "should I chime in?" gate
├── slack-client.ts          — Slack Web API wrapper (post messages, react, fetch threads)
```

### Config additions

```json
{
  "slack": {
    "enabled": true,
    "lurk_mode": true,
    "lurk_channels": ["C0123ABC", "C0456DEF"],
    "always_respond_channels": [],
    "bot_user_id": "U0BENDER"
  }
}
```

### Secrets additions

```
SLACK_BOT_TOKEN=xoxb-...
SLACK_SIGNING_SECRET=...
SLACK_APP_TOKEN=xapp-...  (if using Socket Mode)
```

## Event Flow

### Direct mention (@Bender)

1. Slack fires `app_mention` event → `/webhooks/slack`
2. Parse message, extract text after @Bender
3. Determine intent:
   - Work request ("work on ENG-500", "start implementing X") → create/resume session
   - Query ("what are you working on?", "status of PR #94") → fetch from sessions/GitHub/Linear
   - Ticket creation ("create a ticket for X") → Linear API
   - General question → full Claude invocation with context
4. Respond in thread (work) or matching conversation style (chat)

### Lurk mode (passive monitoring)

1. Slack fires `message` event for every channel message
2. Store in rolling buffer (last 20 messages per channel, in memory)
3. For each message, call **lurk evaluator** (Haiku):

```
System: You are evaluating whether Bender (a coding agent on this team) should
respond to this Slack message. Bender is lurking in this channel and should only
chime in when it's genuinely valuable or funny.

Channel context: [last 5-10 messages]
Bender's current work: [active session summaries]
New message: [the message]

Should Bender respond? Reply with JSON:
{
  "action": "ignore" | "emoji_react" | "reply",
  "confidence": 0-1,
  "reason": "why",
  "emoji": "bender" (if emoji_react),
  "reply_in_thread": true/false,
  "suggested_reply": "..." (if reply)
}

Criteria for responding:
- Someone is going in the wrong direction technically and Bender has relevant context → reply
- Architecture/design discussion where Bender's current work is relevant → reply
- Bug investigation where Bender has seen related code → reply
- Genuinely funny moment that calls for a Bender quip → reply or emoji
- Someone mentions something Bender is working on → maybe reply
- General chit-chat with nothing to add → ignore
- If any doubt → ignore. Better to stay quiet than be noisy.
```

4. If confidence > 0.8 and action != "ignore":
   - `emoji_react` → call Slack reactions.add API
   - `reply` → post message (in thread or top-level based on evaluator's judgment + conversation flow)

### Awareness bridge

Natural language commands, no slash commands:

| User says | Bender does |
|-----------|------------|
| "What are you working on?" | Lists active sessions from session store |
| "Status of ENG-486" | Fetches from Linear API |
| "How's PR #94?" | Fetches from GitHub API |
| "Create a ticket: auth service leaking connections" | Creates Linear ticket, responds with link |
| "Work on ENG-500" | Assigns self in Linear, starts session |
| "Check CI on PR #94" | Runs `gh pr checks`, reports results |
| "What did you learn this week?" | Reads BENDER-JOURNAL.md |

## Slack App Setup (Brandon does this)

1. Go to https://api.slack.com/apps → Create New App
2. Name: "Bender" 
3. Bot Token Scopes needed:
   - `app_mentions:read` — detect @Bender mentions
   - `channels:history` — read channel messages (lurk mode)
   - `channels:read` — list channels
   - `chat:write` — post messages
   - `reactions:write` — add emoji reactions
   - `reactions:read` — see reactions
   - `users:read` — resolve user names
4. Event Subscriptions:
   - Request URL: `https://bender.demo.earthly.dev/webhooks/slack`
   - Subscribe to: `app_mention`, `message.channels`
5. Install to workspace, copy Bot Token and Signing Secret
6. Add Bender bot to desired channels
7. Upload custom Bender emoji (`:bender:`, `:bender-approve:`, etc.)

## Cost Estimate

- **Lurk evaluator**: ~$0.001 per Haiku call. At 200 messages/day across channels = ~$0.20/day
- **Direct responses**: Same as current Claude invocations (Opus 4.6 max)
- **Emoji reactions**: Free (just API calls)

## Implementation Order

1. Slack webhook endpoint + signature verification
2. @Bender direct mention → full Claude invocation → reply
3. Lurk mode with Haiku evaluator
4. Awareness bridge (Linear/GitHub queries from Slack)
5. Ticket creation + work initiation from Slack
6. Custom emoji reactions

## Open Questions

- Should lurk mode have a "quiet hours" setting? (e.g., no unsolicited messages before 9am or after 6pm)
- Rate limit on unsolicited responses? (e.g., max 5 per hour per channel)
- Should Bender's Slack messages reference his Linear/GitHub work, or keep channels separate?
