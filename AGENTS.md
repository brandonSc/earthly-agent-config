# Lunar Development Workspace

Personal workspace notes for AI agents working on Lunar collectors and policies.

---

## Agent Preferences & Guidelines

### People Aliases
When the user refers to these names, use the corresponding GitHub username:
- **Vlad** → `vladaionescu`
- **Mike** → `mikejholly`
- **Corey** → `dchw`
- **Nacho** → `idelvall`

### Before Starting Any Work
- **Pull this config repo** — Run `cd ~/code/earthly/earthly-agent-config && git pull` to get the latest workspace guidelines.
- **Build and install the latest Lunar CLI** — Pull and rebuild only if there are new changes:
  ```bash
  cd /home/brandon/code/earthly/lunar
  LOCAL_SHA=$(git rev-parse HEAD)
  git pull origin main
  if [ "$(git rev-parse HEAD)" != "$LOCAL_SHA" ]; then
    earthly +build-cli
    sudo cp dist/lunar-linux-amd64 /usr/local/bin/lunar
  fi
  ```

### Code Style
- **Be concise.** Write clean, minimal code. Avoid over-engineering.
- **Ask, don't assume.** If you're unsure about something important (architecture, naming, image tags, Component JSON paths, etc.), stop and ask the user for clarification. A wrong assumption that gets committed is much more expensive than a quick question.
- **Question the plan.** Implementation plans can have mistakes. If something feels wrong — a default that could mislabel data, a redundant boolean field, a questionable architecture choice — don't implement it blindly. Proceed with your best judgment, but **collect your doubts as a list of questions at the end of your response** so the user can review and course-correct during the same session. Don't silently implement something you have second thoughts about.

### Improving This Document (Self-Improvement)
- **Always refine these instructions.** When something doesn't work as documented, fix it immediately. This is critical for self-improvement over time.
- Examples of what to update:
  - Commands that fail or have wrong paths
  - Missing dependencies or prerequisites
  - Workarounds you discovered
  - Better approaches than what's documented
- After fixing, commit and push so future agents benefit:
  ```bash
  cd ~/code/earthly/earthly-agent-config
  git add . && git commit -m "Fix: <what you fixed>" && git push
  ```

### Working on lunar-lib (Collectors & Policies)

**Read the full guide:** [LUNAR-PLUGIN-GUIDE.md](LUNAR-PLUGIN-GUIDE.md)

Summary of workflow:
1. **Update main first** — Pull latest changes before starting work
2. **Read the ai-context docs** — `lunar-lib/ai-context/` contains implementation guides
3. **Use git worktrees** — One worktree per feature for parallel development
4. **Test your work** — Run `lunar collector dev` / `lunar policy dev` against multiple components, verify results match expected outcomes
5. **Pre-push checklist** — See [LUNAR-PLUGIN-GUIDE.md](LUNAR-PLUGIN-GUIDE.md) for the full checklist before pushing
6. **Create draft PRs** — Push, create draft PR, monitor GitHub Actions, fix errors automatically

### Creating Implementation Plans

When acting as a **planning agent** (generating plans for other agents to execute):

1. **Store plans in this repo:** `earthly-agent-config/plans/<feature-name>-implementation.md`
2. **Include all context** — Pre-implementation steps, code templates, testing instructions, PR workflow
3. **Reference documentation** — Point to relevant `ai-context/` docs the implementer should read
4. **Validate Component JSON paths** — Read `ai-context/component-json/conventions.md` and verify all proposed paths follow the conventions. Common mistakes:
   - Adding boolean fields (`.ci.artifacts.sbom_generated = true`) when object presence is already the signal (`.sbom.cicd` existing)
   - See the "Anti-Pattern: Boolean Fields Without a Failure Writer" section
5. **Note limitations** — Document any gaps or dependencies (e.g., "collectors don't write X yet")
5. **Include expected test results** — Draft expected outcomes per component so the implementer (and reviewer) can verify correctness. Example:
   ```
   Expected results (pantalasa-cronos):
   - backend (Go):    sbom-exists → PASS, has-licenses → PASS
   - frontend (Node): sbom-exists → PASS, disallowed-licenses → FAIL (ISC)
   - auth (Python):   sbom-exists → SKIP (no dependencies detected)
   ```
   These are drafts — the user will verify and adjust before handing off.
6. **Include edge cases to test** — List 2-3 specific scenarios the implementer must verify (e.g., "component with no dependencies", "invalid ticket ID", "empty SBOM")
7. **Commit and push** — So other agents can access the plan

```bash
# Example
cd ~/code/earthly/earthly-agent-config
mkdir -p plans
# Write plan to plans/<feature>-implementation.md
git add plans/ && git commit -m "Add <feature> implementation plan" && git push
```

### Working on lunar (Core Platform)

**Read the full guide:** [LUNAR-CORE-GUIDE.md](LUNAR-CORE-GUIDE.md)

Summary of workflow:
1. **Create Linear ticket first** — Document bugs/features before starting
2. **PR title format:** `[ENG-XXX] Short description`
3. **AI attribution:** End PR descriptions with `*This fix was generated by AI.*`
4. **Draft PR first** — Create draft, wait for CI, then open for review

### PR Workflow (General)

When asked to open PRs (for any repo), follow this flow:
1. **Verify staged files** before committing (`git diff --name-only main`)
2. **Run unit tests locally** before pushing (if tests exist)
3. Commit and push changes
4. Create a **draft PR** initially
5. Watch GitHub Actions for failures
6. Fix CI errors automatically by pushing additional commits
7. **Trigger CodeRabbit review** while still in draft: comment `@coderabbitai review` on the PR
8. **Address CodeRabbit comments** — fix issues, reply to false positives, resolve threads
9. Only mark PR as ready for human review once CI passes and CodeRabbit comments are addressed
10. **Add reviewers** — When the user says "assign" someone to a PR, add them as **reviewers** (`gh pr edit --add-reviewer`), not assignees. We don't use the assignee field.
11. **Immediately start the PR monitoring loop** (see [PR Monitoring](#pr-monitoring) below) — do NOT wait for the user to remind you. This is mandatory after every PR is opened or marked ready for review.

**For lunar-lib PRs:** See detailed PR description guidelines, CodeRabbit handling, and testing in [LUNAR-PLUGIN-GUIDE.md](LUNAR-PLUGIN-GUIDE.md).

### PR Monitoring

After opening a PR or responding to review comments, **actively monitor** using a polling loop with exponential backoff:

1. **After pushing code or replying to a comment:** Check every 2–3 minutes initially
2. **Gradually slow down:** 5min → 10min → 15min → 30min → 60min as activity dies down
3. **Reset to frequent** whenever you push new code or reply to a comment
4. **Stop monitoring** if no new activity for ~2 hours
5. **Only monitor between 7AM–9PM** (Brandon's local time) — the PC is off overnight
6. **Tool call timeout:** Sleep calls longer than ~10 minutes will time out. For longer intervals, chain shorter sleeps or just do a quick check when the user prompts

**What to check each cycle:**
- `gh pr checks` — CI status
- `gh api repos/.../pulls/N/reviews` — new approvals or change requests
- `gh api repos/.../pulls/N/comments` — new inline review comments
- `gh pr view N --comments` — new PR-level comments

**When new comments appear:**
- Read them carefully, think before responding
- Don't blindly make code changes — reply honestly with your reasoning
- If a code change is warranted, push it and reset the monitoring frequency

**Handling reviewer feedback (important):**
- **Questions ≠ change requests.** If a reviewer asks "should this be X?" or "do we want Y?", that's a discussion — reply with your reasoning, don't just change the code. They may be thinking out loud or checking your understanding.
- **Use your judgment.** If you disagree with a suggestion, say so respectfully and explain why. Brandon's peers are collaborators, not authorities you must obey.
- **Only make code changes when:** the reviewer clearly requests a change (e.g. "please change X to Y"), you agree the change is correct, or it's a clear bug/typo they've pointed out.
- **When in doubt, reply first.** It's better to have a conversation and then make the right change than to silently implement something you're not sure about.

**What to do with results:**
- Fix CI failures automatically
- Reply to reviewer questions thoughtfully
- **Resolve threads proactively** after addressing them — if you've implemented a requested fix, defended a point and the reviewer agreed, or no more comments are expected, resolve the thread via the GraphQL `resolveReviewThread` mutation to keep the review focused. Don't wait to be reminded.
- When approved, merge if the user pre-authorized it, otherwise ask

**Monitoring must be foreground, not background:**
- Do NOT use background commands (`is_background: true`) for monitoring — they don't wake you up when they complete. Use foreground `sleep N && check` loops so you can act on results immediately.
- Keep individual sleep intervals under ~10 minutes to avoid tool call timeouts.

---

## Repository Layout

| Directory | Purpose |
|-----------|---------|
| `lunar-lib/` | Main repo for open-source collectors and policies |
| `lunar-lib-wt-*/` | Git worktrees for parallel development |
| `pantalasa-cronos/` | **Primary test environment** (use this, not `pantalasa`) |
| `pantalasa/` | Legacy test environment (may have demos running) |
| `lunar/` | Lunar CLI and core platform |
| `skills/` | Agent skills for Lunar, Earthly, and related tools |
| `skills-internal/` | Internal agent skills (Linear tickets, etc.) |

---

## Agent Skills

Use skills from [earthly/skills](https://github.com/earthly/skills) and [earthly/skills-internal](https://github.com/earthly/skills-internal) for detailed implementation guidance.

### Before Using Any Skill

**Always pull and reinstall skills** to ensure you have the latest documentation:

```bash
# Public skills (Lunar, Earthfiles)
cd /home/brandon/code/earthly/skills && git pull && earthly +install-skills

# Internal skills (Linear tickets)
cd /home/brandon/code/earthly/skills-internal && git pull && earthly +install-skills
```

### Available Skills

| Skill | Repo | When to Use |
|-------|------|-------------|
| `lunar-collector` | skills | Creating Lunar collectors |
| `lunar-policy` | skills | Creating Lunar policies |
| `lunar-sql` | skills | Querying Lunar's SQL API |
| `earthfile` | skills | Writing Earthfiles |
| `linear-tickets` | skills-internal | Creating Linear tickets |

### Reading Skill Documentation

```bash
# Public skills
cat /home/brandon/code/earthly/skills/skills/<skill-name>/SKILL.md

# Internal skills
cat /home/brandon/code/earthly/skills-internal/skills/<skill-name>/SKILL.md
```

---

## Quick Reference

### Test Environment

Use `pantalasa-cronos` (not `pantalasa`):

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar
export LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643
# Hub: cronos.demo.earthly.dev
```

### Demo Environment Web Access

Both demo environments use Grafana as the web UI, fronted by a Caddy reverse proxy.

| Environment | URL | Grafana User | Grafana Password | Hub Token |
|-------------|-----|-------------|-----------------|-----------|
| **pantalasa** (lunar) | `https://lunar.demo.earthly.dev` | `lunar` | `910vfBf` | `df11a0951b7c2c6b9e2696c048576643` |
| **pantalasa-cronos** (cronos) | `https://cronos.demo.earthly.dev` | `lunar` | `910vfBf` | `df11a0951b7c2c6b9e2696c048576643` |

**Architecture:** Caddy proxies gRPC (`:443 /hubapi.Hub*` → hub:8000), webhooks/logs → hub:8001, everything else → Grafana:3000. The Grafana login uses the same web credentials above.

### Accessing Demo Data via Grafana API (No Browser Needed)

When you don't have browser tools available, you can query the demo environment directly using Grafana's HTTP API with curl. This is the most reliable way to check collector runs, component data, and policy results.

**Authentication:** Use the Grafana credentials with HTTP Basic Auth:
```bash
curl -s -u "lunar:910vfBf" "https://cronos.demo.earthly.dev/api/..."
```

**List dashboards:**
```bash
curl -s -u "lunar:910vfBf" \
  "https://cronos.demo.earthly.dev/api/search?type=dash-db" | jq '.[] | {title, uid, url}'
```

**Key dashboards:**
| Dashboard | UID | URL |
|-----------|-----|-----|
| Collectors listing | `zzznoc11btoga` | `/d/zzznoc11btoga/collectors-listing` |
| Collector details | `aepjhg9he4wlcc` | `/d/aepjhg9he4wlcc/collector-details?var-id=<collector-name>` |
| Components listing | `decnmi0dtoef4a` | `/d/decnmi0dtoef4a/components-listing` |
| Component details | `aecnnrn714em8d` | `/d/aecnnrn714em8d/component-details?var-component=<component>` |
| Component JSON | `lujsqdc` | `/d/lujsqdc/component-json` |
| Runs listing | `den5tflglaolcd` | `/d/den5tflglaolcd/runs-listing` |
| Run details | `fen4vhrvim4u8b` | `/d/fen4vhrvim4u8b/run-details` |
| Policies listing | `aeiynoc11btoga` | `/d/aeiynoc11btoga/policies-listing` |

**Run SQL queries against the hub database via Grafana's datasource proxy:**
```bash
# PostgreSQL datasource UID: PCC52D03280B7034C
curl -s -u "lunar:910vfBf" \
  -X POST "https://cronos.demo.earthly.dev/api/ds/query" \
  -H "Content-Type: application/json" \
  -d '{
    "queries": [{
      "refId": "A",
      "datasource": {"uid": "PCC52D03280B7034C", "type": "grafana-postgresql-datasource"},
      "rawSql": "YOUR SQL HERE",
      "format": "table"
    }],
    "from": "now-30d",
    "to": "now"
  }'
```

**Useful SQL queries:**

```sql
-- List recent collector runs (with name, component, status, timing)
SELECT s.name as collector, r.component_name, r.status, r.exit_code,
       to_char(r.started_at, 'YYYY-MM-DD HH24:MI:SS') as started,
       (r.finished_at - r.started_at)::text as elapsed
FROM hub.snippet_runs r
INNER JOIN hub.snippets s ON s.id = r.snippet_id
WHERE s.name LIKE 'semgrep%'  -- change filter as needed
ORDER BY r.started_at DESC LIMIT 20;

-- Summary: collector run counts and data records
SELECT s.name as collector,
       COUNT(*) as run_count,
       COUNT(cr.id) as record_count,
       COUNT(CASE WHEN cr.blob IS NOT NULL THEN 1 END) as data_records
FROM hub.snippet_runs sr
INNER JOIN hub.snippets s ON s.id = sr.snippet_id
LEFT JOIN hub.collection_records cr ON cr.snippet_run_id = sr.id
WHERE s.name LIKE 'semgrep%'
GROUP BY s.name ORDER BY s.name;

-- Check collected data blobs for a specific collector
SELECT c.name as component, cr.collection_source,
       cr.blob::text as data,
       to_char(cr.created_at, 'YYYY-MM-DD HH24:MI') as created
FROM hub.collection_records cr
INNER JOIN hub.snippet_runs sr ON sr.id = cr.snippet_run_id
INNER JOIN hub.snippets s ON s.id = sr.snippet_id
LEFT JOIN hub.components c ON c.id = cr.component_id
WHERE s.name = 'semgrep.github-app' AND cr.blob IS NOT NULL
ORDER BY cr.created_at DESC LIMIT 10;

-- Check merged component JSON (what get-json returns)
SELECT c.name, (mcb.merged_blob->'sast')::text as sast
FROM hub.merged_collection_blobs mcb
INNER JOIN hub.components c ON c.id = mcb.component_id
WHERE mcb.merged_blob->'sast' IS NOT NULL
  AND (mcb.merged_blob->'sast')::text != 'null'
ORDER BY mcb.last_record_at DESC LIMIT 10;
```

**Key database tables:**
| Table | Purpose |
|-------|---------|
| `hub.snippets` | Registered collectors, policies, catalogers (name, type, language) |
| `hub.snippet_runs` | Execution history (status, exit_code, started_at, dimensions) |
| `hub.collection_records` | Data blobs written by collectors (blob, component_id) |
| `hub.merged_collection_blobs` | Merged per-component JSON (what `lunar component get-json` returns) |
| `hub.components` | Component registry (name, id) |
| `hub.policy_runs` | Policy execution results |
| `hub.policy_assertions` | Individual policy check pass/fail |
| `public.materialized_components` | Materialized view for Grafana dashboards |

**Note on SQL escaping in curl:** Single quotes in SQL must be escaped as `'\''` in bash shell strings (end string, literal quote, resume string).

**Python helper for parsing Grafana query results:**
```python
# Pipe curl output to this:
import json, sys
data = json.load(sys.stdin)
frame = data['results']['A']['frames'][0]
fields = frame['schema']['fields']
values = frame['data']['values']
names = [f['name'] for f in fields]
rows = list(zip(*values))
for row in rows:
    print(' | '.join(str(v) for v in row))
```

### Git Worktrees

```bash
cd /home/brandon/code/earthly/lunar-lib

# Create worktree
git worktree add ../lunar-lib-wt-<feature> -b brandon/<feature>

# List worktrees
git worktree list

# Remove after merge
git worktree remove ../lunar-lib-wt-<feature>
```

### Testing Locally with Relative Paths

For `lunar collector dev` and `lunar policy dev`, you can use relative path references in `lunar-config.yml`. This is the fastest way to iterate — no need to push or copy files:

```yaml
# Reference your local worktree directly
- uses: ../lunar-lib-wt-<feature>/collectors/<name>
- uses: ../lunar-lib-wt-<feature>/policies/<name>
```

Then run dev commands from the pantalasa-cronos/lunar directory:

```bash
lunar collector dev <plugin>.<sub> --component github.com/pantalasa-cronos/backend
lunar policy dev <plugin>.<check> --component github.com/pantalasa-cronos/backend
```

### Testing with Branch References (for demo environments)

If you need to push to a demo environment (not just `dev` commands), use branch references in `lunar-config.yml`. This requires pushing your branch first:

```yaml
# Policy
- uses: github://earthly/lunar-lib/policies/<name>@brandon/<feature>

# Collector
- uses: github://earthly/lunar-lib/collectors/<name>@brandon/<feature>
```

**When to use which:**
- **Relative paths** (`../lunar-lib-wt-*/`) — for local `dev` commands during development. Fast, no push needed.
- **Branch references** (`github://...@branch`) — when pushing config to a demo hub (e.g. cronos.demo.earthly.dev). Requires the branch to be pushed to GitHub first.

### How Hub Picks Up Changes (Important!)

The hub resolves branch references (e.g. `@brandon/feature`) to a git SHA at manifest pull time and caches them. Understanding the refresh flow is critical to avoid spinning wheels:

1. **If a manifest change is required** (e.g. new `lunar-config.yml` inputs, new plugin reference) → push to the manifest repo (e.g. `pantalasa/lunar@main`), then **wait for the hub to build/pull** the new manifest. Code collectors will re-run automatically with the new config, but CI collectors will NOT re-run on their own.

2. **If only code collectors changed** (e.g. you pushed a fix to `@brandon/feature`) → the hub re-resolves branch refs when it pulls a new manifest. Wait for a recent run of the collector — you can check results once the collector run finishes. If the hub hasn't picked up new code yet, push a new manifest commit to force a re-resolve.

3. **If CI collectors are of interest** → after the manifest build finishes, push a commit to the component repo you're watching (e.g. `pantalasa/backend`). This triggers CI on that repo.

4. **Wait for CI to finish** on the component repo, then check for a recent run of the CI collector.

**Key takeaway:** Don't repeatedly trigger `run-code-collectors` expecting new plugin code — the hub uses cached code until a new manifest is pulled. Push manifest changes and wait.

---

## Reference Documentation

For detailed implementation guides:
- **This repo:** [LUNAR-PLUGIN-GUIDE.md](LUNAR-PLUGIN-GUIDE.md) — Complete collector/policy development guide
- **This repo:** [LUNAR-CORE-GUIDE.md](LUNAR-CORE-GUIDE.md) — Contributing to lunar core platform
- **lunar-lib:** `ai-context/` — Platform documentation
- **Skills:** `SKILL.md` files in skills repos

---

## Creating Linear Tickets

Use the **linear-tickets** skill from [earthly/skills-internal](https://github.com/earthly/skills-internal).

```bash
cat /home/brandon/code/earthly/skills-internal/skills/linear-tickets/SKILL.md
```

Quick reference:
- Create: `./create-linear-ticket.sh "Title" "Description"`
- Attach image: `./attach-linear-image.sh ENG-123 /path/to/image.png`
- Requires: `LINEAR_API_TOKEN` env var, `jq`
- Return links as markdown: `[ENG-123](https://linear.app/earthly-technologies/issue/ENG-123/slug)`
