# Semgrep Collector - Agent Handoff Summary

## Current Task
Testing the Semgrep collector PR in the `pantalasa-cronos` environment. The PR is at `lunar-lib-wt-semgrep` branch `brandon/semgrep`.

## What's Been Done

### 1. Semgrep collector implemented with 3 sub-collectors:
- **`github-app`** - Detects Semgrep GitHub App check-runs on PRs (code collector)
- **`running-in-prs`** - Queries Lunar Hub DB to verify Semgrep ran on recent PRs, provides compliance proof for default branch (code collector)
- **`cli`** - Detects Semgrep CLI execution in CI (CI collector, runs native)

### 2. Key architectural decisions:
- Code collectors use `default_image: earthly/lunar-lib:base-main`
- CI collectors use `default_image_ci_collectors: native` (for performance)
- `psql` was added to `earthly/lunar-lib:base-main` image (separate PR merged)
- `running-in-prs` collector uses `lunar sql connection-string` for DB access (with fallback to `LUNAR_SECRET_PG_PASSWORD`)

### 3. PR status:
- Draft PR open on `lunar-lib`
- CodeRabbit reviewed
- Vlad's comments addressed
- Renamed `github-app-default-branch` → `running-in-prs` for clarity

## What Needs Testing

The `running-in-prs` collector needs end-to-end testing in Cronos:
- User confirmed `lunar sql` commands should work now on Cronos
- Need to verify the collector produces data when run against a component
- The `github-app` collector also needs a real PR with Semgrep checks to populate data

## Test Environment

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar
export LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643
```

**Cronos Hub:** https://cronos.demo.earthly.dev

**Test components:**
- `github.com/pantalasa-cronos/backend` (Go)
- `github.com/pantalasa-cronos/frontend` (Node.js)
- `github.com/pantalasa-cronos/kafka-go` (Go)

## Test Commands

```bash
# Test running-in-prs collector
lunar collector dev semgrep.running-in-prs --component github.com/pantalasa-cronos/backend --verbose

# Test github-app collector
lunar collector dev semgrep.github-app --component github.com/pantalasa-cronos/backend --verbose

# Check component JSON after collection
lunar component get-json github.com/pantalasa-cronos/backend | jq '.sast, .sca'
```

## Files of Interest

| Path | Description |
|------|-------------|
| `/home/brandon/code/earthly/lunar-lib-wt-semgrep/collectors/semgrep/` | The collector code |
| `/home/brandon/code/earthly/lunar-lib-wt-semgrep/collectors/semgrep/lunar-collector.yml` | Collector manifest |
| `/home/brandon/code/earthly/lunar-lib-wt-semgrep/collectors/semgrep/running-in-prs.sh` | DB query collector |
| `/home/brandon/code/earthly/lunar-lib-wt-semgrep/collectors/semgrep/github-app.sh` | GitHub App collector |
| `/home/brandon/code/earthly/lunar-lib-wt-semgrep/collectors/semgrep/cli.sh` | CI collector (native bash) |
| `/home/brandon/code/earthly/pantalasa-cronos/lunar/lunar-config.yml` | Test environment config |

## lunar-config.yml Reference

The Semgrep collector is referenced in `pantalasa-cronos/lunar/lunar-config.yml` using a relative path for local testing:

```yaml
collectors:
  - uses: ../lunar-lib-wt-semgrep/collectors/semgrep
```

## Known Issues / Context

1. **`LUNAR_COMPONENT_ID` bug** - Fixed and verified. `lunar collector dev` now correctly sets `LUNAR_COMPONENT_ID`, `LUNAR_COMPONENT_GIT_SHA`, and all other env vars.
2. **`LUNAR_HUB_HOST` for SQL** - User configured Cronos to pass this to collectors, should work now
3. **`running-in-prs` depends on PR data** - This collector queries DB for Semgrep check-runs on PRs. If no PRs have been scanned with Semgrep GitHub App, it won't find data.

## Browser Tool Setup (Pending)

User wants the agent to navigate the Lunar UI directly to check collector results. Cursor's built-in browser tool shows "Ready (Chrome detected)" but wasn't available in previous sessions. May need:
- Check Cursor MCP settings
- Restart Cursor after enabling
- Ensure Chrome is running

## Next Steps

1. Test `running-in-prs` collector in Cronos with `lunar collector dev`
2. Verify data appears in component JSON
3. If browser tools work, navigate to Cronos UI to verify visually
4. Mark PR ready for review once testing passes
