# Runs Listing Grouping — Implementation Plan

## Problem

The Runs listing dashboard (`runs.json`, UID `den5tflglaolcd`) shows **every individual run as a separate row**. When CI-otel collectors fire per-job (e.g. `ci-otel.cmd-start`, `ci-otel.cmd-end`), a single CI build can produce **hundreds of rows** (526 `ci-otel.cmd-start` + 521 `ci-otel.cmd-end` in the last 6 hours for `backend` alone). These flood the view and push all other collectors/policies off-screen.

## Proposed Solution: Grouped Summary View

Replace the flat individual-run table with a **grouped summary table** that collapses runs by script name. Each row represents a unique script, with an aggregated count and status summary. Clicking a row drills down to the existing individual-run view filtered to that script.

### Current State (runs.json)

The dashboard has **3 panels** (excluding the nav header):
1. **Queued** — jobs waiting in the River queue (panel id 6)
2. **Active** — the main runs table, one row per run (panel id 1)
3. **Pagination** — page controls (panel id 7)

### New State: Two-Level View

#### Level 1: Grouped Summary (default view)

A new SQL query replaces the existing "Active" panel query. It `GROUP BY` script name (and optionally component + SHA for finer grouping) and returns:

| Column | Description |
|--------|-------------|
| Status | Overall status emoji: 🏁 if all succeeded, ⚠️ if any failed, 🔄 if any running |
| Script type | collector / policy / cataloger |
| Script name | e.g. `ci-otel.cmd-start` |
| Component | repo name (when filtered to a single component) |
| Runs | Count of runs in this group |
| ✅ | Count of successful runs |
| ⚠️ | Count of failed runs |
| Latest | Timestamp of most recent run (as "time ago") |
| Duration (avg) | Average duration across runs |

**Clickable drill-down:** The "Script name" column links to the **same runs-listing dashboard** but with `var-prefix` set to the script name. This reloads the page filtered to that single script — where it falls below the threshold for grouping and shows individual runs (see "Transition Logic" below).

#### Level 2: Individual Runs (drill-down)

When `var-prefix` is set to a specific script name (e.g. `ci-otel.cmd-start`), the view shows the **existing individual-run table** — no change needed. The breadcrumb already handles `prefix` and shows `Runs > ci-otel.cmd-start`.

### Transition Logic (Key Design Decision)

**Always group.** The grouped view is the default. When `prefix` is set (i.e., the user has drilled into a specific script), show individual runs. This uses the existing `$prefix` variable that already exists and is already wired into breadcrumbs.

Logic:
- `$prefix = ''` → show **grouped summary** table
- `$prefix != ''` → show **individual runs** table (existing behavior)

In Grafana, this can be achieved by having **two panels** with conditional visibility, or more pragmatically, by using **two separate queries** in the same panel and toggling via a Grafana transformation. However, Grafana's native conditional panel visibility is limited. The cleanest approach:

**Use two separate table panels, each with a SQL `WHERE` guard:**
- Panel A (grouped): SQL returns rows only when `'$prefix' = ''`
- Panel B (individual): SQL returns rows only when `'$prefix' != ''`

Both panels occupy the same `gridPos`, and one will always be empty (Grafana hides empty tables cleanly with `"noValue"` message or zero height).

Actually, the simplest approach: **use a single panel with two queries** — Grafana table panels support multiple queries, but they show separate tables. Instead, use a **single query that branches**:

```sql
-- When prefix is empty: return grouped view
-- When prefix is set: return individual runs
```

This can be done with a SQL `UNION ALL` with mutually exclusive guards, but that gets messy.

**Recommended approach: Two panels stacked, each with a guard clause.** Panel A (grouped) returns empty when prefix is set. Panel B (individual) returns empty when prefix is empty. Set Panel B's `gridPos` to overlap or be adjacent. Both panels titled "" so they look seamless.

### Grouped Summary SQL

```sql
-- Grouped summary (only when $prefix is empty)
SELECT
  CASE
    WHEN SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) > 0 THEN '🔄'
    WHEN SUM(CASE WHEN exit_code != 0 AND status = 'finished' THEN 1 ELSE 0 END) > 0 THEN '⚠️'
    ELSE '🏁'
  END AS group_status,
  type,
  name,
  CASE
    WHEN type = 'policy' THEN 'd/deiyog5h3tzi8d/policy-details?orgId=1&from=now-6h&to=now&timezone=browser&var-initiative=standardization&var-policy=' || name
    WHEN type = 'collector' THEN 'd/aepjhg9he4wlcc/collector-details?orgId=1&from=now-6h&to=now&timezone=browser&var-id=' || name
    WHEN type = 'cataloger' THEN 'd/aepjhg9he4wlcc/collector-details?orgId=1&from=now-6h&to=now&timezone=browser&var-id=' || name
    ELSE ''
  END AS script_link,
  -- Drill-down link to the same dashboard with prefix set
  '/d/den5tflglaolcd/runs-listing?var-prefix=' || name
    || '&orgId=1&from=now-6h&to=now&timezone=browser&var-page=1&var-page_size=50'
    || '&var-snippet_id=&var-status=' || '$status'
    || '&var-component=' || '$component'
    || '&var-snippet_type=' || '$snippet_type'
    || '&var-snippet_name=$__all'
    || '&var-sha=' || '$sha'
    || '&var-pr=' || '$pr'
    || '&var-reruns=' || '$reruns' AS drill_link,
  COUNT(*) AS total_runs,
  COUNT(*) FILTER (WHERE exit_code = 0 AND status = 'finished') AS success_count,
  COUNT(*) FILTER (WHERE exit_code != 0 AND status = 'finished') AS fail_count,
  COUNT(*) FILTER (WHERE status = 'running') AS running_count,
  MAX(started_at) AS latest_run,
  MAX(started_at) AS latest_run2,  -- for tooltip
  AVG(EXTRACT(EPOCH FROM (finished_at - started_at))) FILTER (WHERE finished_at IS NOT NULL) AS avg_duration
FROM (
  -- Base query: reuse existing filtering logic
  SELECT
    r.started_at,
    r.finished_at,
    r.exit_code,
    r.status,
    s.name,
    s.type,
    p.state as pr_state,
    r.dimensions ->> 'repo_name' AS repo_name,
    r.dimensions ->> 'head_sha' AS head_sha,
    r.dimensions ->> 'manifest_version' AS manifest_version
  FROM hub.snippet_runs r
  INNER JOIN hub.snippets s ON s.id = r.snippet_id
  LEFT OUTER JOIN hub.git_pull_requests p ON r.git_pull_request_id = p.id
  WHERE
    ('$pr' = 'All' OR r.dimensions ->> 'pr' = '$pr')
    AND (s.name IN (${snippet_name:sqlstring}))
    AND (s.type IN (${snippet_type:sqlstring}))
    AND ('$component' = 'All' OR r.dimensions ->> 'repo_name' = '$component')
    AND (p.state IS NULL OR p.state != 'closed')
) base
WHERE
  ('$sha' = 'All' OR head_sha = '$sha')
  AND (
    '$status' = 'All'
    OR ('$status' = 'Success' AND exit_code = 0)
    OR ('$status' = 'Fail' AND exit_code != 0)
    OR ('$status' = 'Running' AND status = 'running')
  )
  -- Guard: only return results when prefix is empty (grouped mode)
  AND '$prefix' = ''
GROUP BY type, name
ORDER BY
  -- Sort: failed groups first, then by latest run
  CASE
    WHEN SUM(CASE WHEN exit_code != 0 AND status = 'finished' THEN 1 ELSE 0 END) > 0 THEN 0
    WHEN SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) > 0 THEN 1
    ELSE 2
  END,
  MAX(started_at) DESC
```

**Note:** This drops the `is_equal_to_latest` manifest version filter and the policy dedup `KEEP` logic from the grouped view. That's intentional — the grouped view is a summary of *all* runs, and the detailed view (drill-down) still applies those filters. The count represents "how many times did this script execute" which is the useful metric for understanding noise.

However, if we want the grouped counts to match the individual view's filtered counts, we should include the `is_equal_to_latest` filter. This is a UX tradeoff — I'd recommend **including it** for consistency. The query above can be wrapped with the same CTE approach.

### Individual Runs SQL

The existing query stays exactly as-is, but add the guard clause:

```sql
AND (
  '$prefix' = ''
  OR s.name = '$prefix'
  OR s.name LIKE '$prefix' || '.%'
)
```

This already exists in the current query! So the individual view is **already correct** — it already filters by `$prefix`. The only change is that when `$prefix = ''`, we show the grouped view instead.

## Impact on Other Dashboards

### 1. Links FROM Other Dashboards TO Runs Listing

All existing links from other dashboards to the runs listing use `var-prefix=` (empty). These will now land on the **grouped summary** instead of the flat list. This is actually an improvement — the grouped view is more useful as a landing page.

Dashboards that link to runs listing (all using `var-prefix=`):
- `component.json` — "collectors" and "policies" links in the header breadcrumb
- `pr.json` — "collectors" and "policies" links, plus error links
- `collector.json` — "Runs" column links (uses `var-snippet_name` filter, which still works)
- `policy.json` — "Runs" column links
- `initiative.json`, `initiatives.json`, `domain.json`, `domains.json`, `home.json` — nav bar error link
- `run.json` — breadcrumb back to runs listing

**Special case: `collector.json`** — The collector detail page has a "Runs" column that links to runs-listing with `var-snippet_name=${__data.fields.Name}`. This filters to a *single* snippet name, so the grouped view will show just one row. That's fine — clicking it drills down to individual runs. Alternatively, we could make the grouped view detect when only one script is filtered and auto-show individual runs. But keeping it as the grouped view with a single row is simpler and consistent.

**Better option for collector.json:** Change the link to use `var-prefix=${__data.fields.Name}` instead of `var-snippet_name`. This would skip the grouped view and go directly to individual runs for that script — which is what users want when clicking "Runs" on a specific collector.

### 2. Policy Runs

Policy runs go through the **same runs listing dashboard**. The grouping applies equally to policies. Since policies typically have one run per component per SHA (with dedup), they produce far fewer rows and grouping is less critical but still works fine. A policy like `codeowners.valid` with 3 runs across 3 components would show as one row with "3 runs".

**Key consideration:** The existing filter `var-snippet_type=policy` still works. When someone filters to just policies, the grouped view shows only policy scripts. Drill-down shows individual policy runs.

### 3. The `var-snippet_name` Filter

Currently, `var-snippet_name` is a multi-select that can filter to specific scripts. In the grouped view, this still works — if someone selects `ci-otel.cmd-start` only, the grouped view shows just that one row. This is a natural fit.

### 4. Pagination

The pagination panel (panel id 7) counts total rows. In the grouped view, this counts *groups* not individual runs. This is correct behavior — if there are 15 distinct scripts, pagination shows 15 total and fits on one page. The drill-down (individual) view keeps the current pagination counting individual runs.

The pagination SQL (panel id 7) needs to be duplicated with the same guard logic:
- `$prefix = ''` → count groups
- `$prefix != ''` → count individual runs (existing)

### 5. `count_failed_latest_runs()` Function

The nav bar's error badge calls `grafana.count_failed_latest_runs()`. This is independent of the runs listing display and counts errors server-side. **No change needed.**

## Files to Modify

| File | Change |
|------|--------|
| `lunar/grafana/dashboards/runs.json` | Main changes: add grouped panel, modify individual panel guard, update pagination |
| `lunar/grafana/dashboards/collector.json` | Change "Runs" link from `var-snippet_name` to `var-prefix` for direct drill-down |

## Implementation Steps

### Step 1: Add Grouped Summary Panel

In `runs.json`, add a new table panel (panel id 8) at the same `gridPos` as the current "Active" panel (y: 8). This panel:
- Uses the grouped SQL query above
- Has column overrides for: Script name (clickable via `drill_link`), Status, Type, Runs count, ✅/⚠️ counts, Latest, Avg Duration
- Hides helper columns (`drill_link`, `script_link`)
- Returns empty when `$prefix != ''`

### Step 2: Guard the Individual Runs Panel

The existing "Active" panel (id 1) already has the `$prefix` filter. When `$prefix = ''`, it currently returns ALL runs. Change: add `AND '$prefix' != ''` to the WHERE clause so it returns empty in that case. Individual runs will only appear when drilling down.

Wait — actually, the current behavior when `$prefix = ''` is to show all runs (the `$prefix` filter becomes a no-op: `'$prefix'='' OR ...`). We need to change this so when `$prefix = ''`, the individual panel returns nothing.

Change the prefix filter from:
```sql
AND (
  '$prefix'=''
  OR s.name = '$prefix'
  OR s.name like '$prefix'||'.%'
)
```
to:
```sql
AND '$prefix' != ''
AND (
  s.name = '$prefix'
  OR s.name like '$prefix'||'.%'
)
```

### Step 3: Update Pagination Panel

The pagination panel (id 7) has the same SQL as the main panel wrapped in `COUNT(*)`. Apply the same dual approach:
- When `$prefix = ''`: count grouped rows
- When `$prefix != ''`: count individual runs with prefix filter

### Step 4: Update Queued Panel

The "Queued" panel (id 6) shows jobs in the River queue. This is already separate and not affected by grouping. **No change needed.**

### Step 5: Update Collector Detail Link

In `collector.json`, change the "Runs" column link from:
```
var-snippet_name=${__data.fields.Name}&var-reruns=true
```
to:
```
var-prefix=${__data.fields.Name}&var-reruns=true
```

This makes clicking "Runs" on a collector go directly to the individual runs view (drill-down), skipping the grouped view.

### Step 6: Breadcrumb Updates

The breadcrumb helper `getBreadScrumbs` already handles `prefix` and shows it in the breadcrumb. When `prefix` is set, it shows `Runs > ci-otel.cmd-start`. This is already correct. The breadcrumb link to "Runs" resets `prefix` to empty, which returns to the grouped view. ✅

## UX Details

### Grouped Panel Column Configuration

| Column | Width | Clickable? | Notes |
|--------|-------|-----------|-------|
| Status (overall) | 69px | No | 🏁/⚠️/🔄 |
| Script type | 94px | No | Color-coded (green=collector, purple=policy) |
| Script name | 234px | Yes → drill-down (same dashboard with prefix) | |
| Runs | 80px | Yes → drill-down | Total count |
| ✅ | 60px | No | Success count |
| ⚠️ | 60px | No | Fail count |
| Latest | 156px | No | Time ago |
| Avg Duration | 110px | No | In seconds |

### Empty State

When the grouped view has no data (e.g., no runs in the time range), Grafana shows its default "No data" message. No special handling needed.

## Open Questions

1. **Should the grouped view include the `is_equal_to_latest` manifest filter?** Including it makes counts consistent with the individual view but adds query complexity. Excluding it gives a "total runs ever" count which may be more intuitive for understanding noise. **Recommendation: include it** for consistency.

2. **Should grouping be per-script only, or per-script-per-component?** If filtering by `$component = All`, should `ci-otel.cmd-start` show as one row with 1000+ runs across all components, or separate rows per component? **Recommendation: per-script only** (one row per script name). The component filter narrows it down if needed. This keeps the grouped view compact.

3. **Should we add a "View mode" toggle?** A Grafana variable to switch between grouped/flat. **Recommendation: No** — use `prefix` as the natural toggle. Keep it simple.
