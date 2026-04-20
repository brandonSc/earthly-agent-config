# Monorepo Support in Lunar — Design Exploration

**Status:** Draft, exploratory — based on code reading + a live test environment
**Date:** 2026-04-20
**Author:** Brandon (with AI assistance)
**Scope:** Code collectors first. CI collector design is briefly sketched at the end but the focus here is on the substrate that everything builds on.

---

## TL;DR

Lunar today has a paper feature for monorepo subdirectory components: the name schema supports `github.com/org/repo/subdir`, the parser recognizes the subdir field, and the hub associates subdir components with their git repo correctly. But the *runtime* (push-time filter, collector working directory, cron-collector repo lookup, dashboards) doesn't honor the subdir in any consistent way. The result is that subdir components register in the hub, get auto-associated with their repo, and then mostly produce empty data — while occasionally surfacing latent bugs in unrelated dashboard code.

Three targeted fixes unlock most of the value:

1. **Filter fix** — make the push-time component filter match a component like `github.com/org/mono/svc-a` against a repo push for `github.com/org/mono`.
2. **WorkDir scoping** — `cd` into the component's subdir before running a code collector for a subdir component.
3. **Cron owner/repo lookup** — use `fetch.ParseComponentName` in cron-collect, not `git.ParseOwnerRepo`.

Everything else (CI attribution, per-service file discovery, cross-component pull ordering, `lunar.yml` in subdirs) builds on those.

---

## Test environments

- **`pantalasa-cronos/monorepo`** (cronos hub, `cronos.demo.earthly.dev`) — primary test repo.
- **`pantalasa/monorepo`** (pantalasa hub, `lunar.demo.earthly.dev`) — mirror, used because the cronos Grafana password from `AGENTS.md` is stale.
- Both have 3 or 4 declared components (`services/backend-go`, `services/api-python`, `compliance`, plus a bare-repo entry on pantalasa) and a new local `release-bundle` collector modeled on the `terraform-internal` cross-component pull pattern.

---

## Current state of monorepo support in Lunar (evidence-based)

### What the code says

**The name schema understands subdir.** [`lunar/snippets/fetch/componentname.go`](lunar/snippets/fetch/componentname.go) parses a component name as `<source>/<org>/<repo>[/<subdir>]` and exposes a `Subdir` field on `ComponentName`. The repolister in [`lunar/snippets/fetch/repolister.go`](lunar/snippets/fetch/repolister.go) preserves `Subdir` on the synced component entry:

```go
// While we plan to support subdirectories, and wildcard subdirectories,
// we do not support them here yet.
```

That comment is from ~1 year ago and is still accurate. The parser works, but the runtime doesn't consume `Subdir`.

**The stored component does NOT retain the subdir as a separate field.** [`lunar/snippets/fetch/fetch.go`](lunar/snippets/fetch/fetch.go) defines `LocalComponent` with `Name, Owner, Description, DomainID, Branch, Tags, CIPipelines` — no `Subdir`. Same in [`lunar/hub/store/components.go`](lunar/hub/store/components.go): the `components` table has `name, owner, description, domain_id, created_at, ci_pipelines, branch, tags, deleted` — no subdir column. So `Subdir` is parsed and then effectively dropped; only `Name` (which includes the full subdir-y string) survives.

**Webhook push filter uses `MatchStar(comp.Name, repo)`.** In [`lunar/hub/filter/filter.go:253`](lunar/hub/filter/filter.go):

```go
if !str.MatchStar(comp.Name, repo) {
    continue
}
```

where `repo = path.Join("github.com", dims["repo_owner"], dims["repo_name"])` (e.g. `github.com/pantalasa/monorepo`) and `comp.Name` is the declared full component name (e.g. `github.com/pantalasa/monorepo/services/backend-go`). [`str.MatchStar`](lunar/util/str/str.go) is either exact match or prefix match (when the *pattern* ends with `*`). For a subdir component name like `github.com/org/mono/svc-a`, the pattern doesn't end with `*` and isn't equal to `github.com/org/mono` — so the filter returns false. Subdir components are therefore excluded from code-collector fanout on push.

**Code-collector `workDir` is always the repo root.** [`lunar/hub/collect/collect.go:137-140`](lunar/hub/collect/collect.go):

```go
workDir := filepath.Join(
    c.codeRunnerPath,
    fmt.Sprintf("%s-%s-%s", gitURI.Org, gitURI.Project, collectionID),
)
```

No subdir appended. The clone happens at that root, and [`lunar/hub/collect/executor.go:196`](lunar/hub/collect/executor.go) passes it directly to [`runner.Execute(ctx, workDir, ...)`](lunar/snippets/executor.go) which sets `cfg.Dir = workDir` on the engine. Every code collector for every component associated with the repo runs with `cwd = repo-root`. A collector like `readme` that does `find . -name README.md` will find the *repo-root* README, not the service's README, regardless of what subdir the component claims to represent.

**Cron-collector uses `ParseOwnerRepo` which takes the last two slash-separated segments.** [`lunar/hub/queue/workers/croncollect/worker.go:141`](lunar/hub/queue/workers/croncollect/worker.go) calls [`git.ParseOwnerRepo(comp.Name)`](lunar/util/git/uri.go) which for `github.com/org/mono/svc-a` returns `owner=mono, repo=svc-a`. The subsequent `gitStore.GetRepositoryByName(repoName)` looks for a repo called `svc-a`, which doesn't exist. So cron collectors silently skip subdir components ("repo not found in git store, skipping").

**Git-repo association does work.** The cataloger runner ([`lunar/hub/cataloger/runner.go`](lunar/hub/cataloger/runner.go)) calls `repoSyncer.SyncComponentRepo(ctx, comp.ID, comp.Name, comp.Branch)` on every component at manifest-load time. That function ([`lunar/hub/gitsync/github.go:123`](lunar/hub/gitsync/github.go)) uses `fetch.ParseComponentName` **correctly** — it extracts `name.Org` and `name.Repo` (ignoring `Subdir`) and looks up the right GitHub repo. So `hub.git_repository_components` ends up with a correct row for every subdir component. This is what makes downstream joins (e.g. `checks_latest` joining via `git_repository_components`) work for subdir components when they do work.

**`lunar.yml` per-component files are documented but not implemented.** The docs ([`lunar/docs/lunar-yml/lunar-yml.md`](lunar/docs/lunar-yml/lunar-yml.md), [`lunar/docs/lunar-config/components.md`](lunar/docs/lunar-config/components.md)) describe `lunar.yml` as an alternative to central `lunar-config.yml` declaration. Grepping the codebase shows the docs are the only reference; no code reads a `lunar.yml` file. This matters because monorepo teams often want to co-locate service config with the service directory.

### What the live test confirms

Pushed to `pantalasa/monorepo` multiple times with 3 subdir components declared in `engineering.monorepo`. After manifest sync + push + `lunar hub run-code-collectors` rerun:

- **Hub components materialized:** All declared components exist in `hub.components` with correct domain, tags, branch.
- **Git-repo association:** All components correctly associated with the `monorepo` git repo in `hub.git_repository_components`.
- **Collection records:** **Zero** rows in `hub.collection_records` for any of the 4 monorepo components. No collector produced any data.
- **Checks:** **Only `services/api-python` ended up with check rows** — 25 pass, 28 fail, 42 skipped, 1 null (96 total, at git_sha `427d5464`). The other three subdir components (`services/backend-go`, `compliance`, bare `monorepo`) have zero check rows. Root cause of the asymmetry is unclear — likely a filter race given the push-time filter shouldn't match any of them, but api-python is consistently the one that gets through. **This asymmetry is itself a concerning signal** — nondeterministic behavior in the filter path.
- **`lunar component get-json`:** `api-python` returns `{}` (exists, empty JSON); the other three return `NotFound` (not in `components_latest`). api-python is the only one the SHA-based view finds because checks_latest has rows for it.
- **Grafana dashboards:** The `Components listing` dashboard's `All Components` panel crashed with `Error transforming data: Cannot read properties of undefined (reading 'trim')` — caused by a SQL mismatch between the panel's two queries, *exposed* by the new components but not strictly caused by monorepo. Details below.
- **Auto-cataloged ghost component:** The pantalasa env runs a `github-org` cataloger every 5 minutes which auto-created `github.com/pantalasa/monorepo` (the bare repo name) as a component in the `other` domain with just the `github-visibility-public` tag. When we later declared the same bare name in `engineering.monorepo`, the declared entry absorbed the cataloger's tags (good — this works by design via name-based merge) but it's easy to miss that this will happen anywhere a github-org cataloger is running.

### Summary of current state

| Area | Works for subdir? | Notes |
|------|-------------------|-------|
| Name parsing (`ParseComponentName`) | Yes | `Subdir` field exists but is dropped after parse. |
| Manifest-level storage | Partial | `Name` preserves the full string; `Subdir` is not separately stored. |
| Domain/tag/branch registration | Yes | Component appears in `hub.components` with correct metadata. |
| Git-repo association (`SyncComponentRepo`) | Yes | Correctly associates all subdir components with the right git repo. |
| Webhook push → collector fanout | **No** | `MatchStar(comp.Name, repo)` is exact-or-prefix and fails for subdir names. |
| Code collector `workDir` | **No** | Always the repo root; never cd's into the subdir. |
| Cron collector repo lookup | **No** | `ParseOwnerRepo` returns `owner=mono, repo=svc-a` for subdir names. |
| CI collector component matching (`matchingComponents`) | **No** | Same `MatchStar` bug ([`lunar/ci/observe.go:866`](lunar/ci/observe.go)). Attribution is inherently limited by CI data being per-repo. |
| `grafana.components` view | Partial | Depends on `components_latest` populating, which depends on upstream collection running. Subdir components mostly miss the view. |
| `lunar.yml` in-subdir declaration | **No** | Documented but unimplemented. |
| Dashboards | **Fragile** | Subdir components exposed a crashing SQL-join mismatch in `components-listing`. |

---

## Design options

I'll explore these on four independent axes. Fixing any one of them is net-positive; fixing all four gives you a working monorepo story.

### Axis 1 — Subdir as a first-class component field

**The question:** should `Subdir` be a first-class column on components, or remain an implicit part of `Name`?

**Option 1a — First-class `path:` field on components.**

```yaml
components:
  github.com/org/mono/services/backend-go:
    path: services/backend-go      # NEW — explicit subdir path from repo root
    owner: ...
    domain: ...
```

The name stays as-is for URL-like identity. `path` is stored as a separate column on `hub.components`. All downstream logic (filter, workDir, cron lookup) consumes `path` instead of re-parsing `Name`. Most explicit, easiest to teach, easy to migrate to.

**Option 1b — Keep `Name` as the canonical subdir source; hydrate `Subdir` from it everywhere.**

No schema change; derive `Subdir` from `Name` wherever needed. Simpler migration path. But less explicit, and creates a weird coupling where the name string is both identity and behavior.

**Option 1c — Allow BOTH: `Name` parses subdir by default; `path:` overrides.**

Best of both worlds but more complexity. Useful for the (rare) case where the component name for identity purposes doesn't match the actual path (e.g. `github.com/org/mono/frontend` identifies a component whose actual path is `apps/web`).

**Recommendation:** **1a** with soft-deprecation of the 4-part-name-implies-subdir pattern. Explicit is clearer, makes config review easier, and matches how other tools (Backstage `spec.sourceLocation`) handle this.

### Axis 2 — Push-time filter matching for subdir components

**The question:** what should `filterComponents` do when a push lands on repo `github.com/org/mono` and components `github.com/org/mono/svc-a`, `github.com/org/mono/svc-b` exist?

**Option 2a — Prefix match with path-boundary awareness.**

Change the filter to match `comp.Name` against `repo` using the `(Source, Org, Repo)` prefix. Specifically:

```go
parsed, err := fetch.ParseComponentName(comp.Name)
if err != nil {
    continue
}
if fmt.Sprintf("%s/%s/%s", parsed.Source, parsed.Org, parsed.Repo) != repo {
    continue
}
```

Matches all components (subdir or not) whose repo identity matches the pushed repo. Also handles wildcards (`github.com/org/mono-*`) correctly because `ParseComponentName` + `IsWildcardRepo` already handle that.

**Option 2b — Rewrite `MatchStar` to be subdir-aware.**

Bigger refactor. Probably unnecessary; 2a is surgical.

**Option 2c — Keep current behavior; require explicit wildcard components for monorepos.**

i.e. a user wanting to track a monorepo as multiple components would declare `github.com/org/mono/*` once and live with no per-subdir distinction. This is essentially the status quo and doesn't meet the monorepo use case.

**Recommendation:** **2a**. Single surgical change in one function. This single fix would have produced check data for all 3 subdir components in our test, not just api-python.

### Axis 3 — `workDir` scoping for code collectors

**The question:** where does a code collector `cd` before running?

**Option 3a — `cd Subdir` before running, only for collectors that opt in.**

Hooks gain an optional `scope: subdir` or `path: true` flag. Collectors that opt in run in the component's subdir. Default stays at repo root (backwards compatible).

```yaml
hook:
  type: code
  scope: subdir     # NEW — run in the component's subdir for subdir components
```

Good for new collectors; existing collectors keep working.

**Option 3b — Always `cd` into `Subdir` for any component that has one.**

Breaking change. Every existing collector needs to be audited for "does this make sense at subdir scope vs repo scope?" (readme, codeowners, k8s, terraform all want subdir scope for a subdir component; but something like `jira` that's metadata-only doesn't care).

**Option 3c — Opt-in via component metadata.**

Add `scope: subdir` on the component itself; all collectors running for that component get the cd. Inverts the opt-in model.

**Recommendation:** **3a** short-term, evolving to **3c** long-term. Opt-in on the hook is safe; opt-in on the component captures "this is a monorepo-subdir component, treat it as such" more naturally once we have enough adoption to justify the breaking change.

**Important corollary:** when 3a/3c lands, we also need a convention for how collectors discover "global" files that should be read from the repo root even when the collector is scoped to a subdir (e.g. a repo-wide `CODEOWNERS`). Options:

- Environment variable `LUNAR_COMPONENT_REPO_ROOT` pointing to the clone root (trivial to add).
- `find_command` input values like `--path $LUNAR_COMPONENT_REPO_ROOT/CODEOWNERS` to let the user choose.
- A `files:` input on the collector with `repo` vs `subdir` semantics (heavier).

The env var is probably sufficient; existing collectors that need repo-root access can opt into reading it.

### Axis 4 — Cross-component data pull primitives

**The question:** `lunar component get-json` works today, but has no ordering or freshness guarantees. When `release-bundle` pulls the `compliance` component's JSON, whether compliance has been collected *for this commit* is a coin flip. The `terraform-internal` pattern in [`pantalasa/lunar`](https://github.com/pantalasa/lunar/tree/main/collectors/terraform-internal) copes by reading whatever's there, but that means the "release bundle" for a backend-go commit might include a compliance snapshot from 10 minutes ago, not from the current commit.

**Option 4a — `dependsOn:` on collectors.**

```yaml
collectors:
  - uses: ./collectors/release-bundle
    on: [monorepo-service]
    dependsOn:
      component: github.com/org/mono/compliance
      collector: dr-docs
```

The hub runs release-bundle only after `dr-docs` has completed for the current commit on the dependency component. Requires a dependency graph and ordering in the collector fanout.

**Option 4b — Staged code-collector phases.**

Introduce two hook types: `code` (runs first in parallel) and `code-post-bundle` (runs after all `code` hooks for all matching components on the repo have completed). The release-bundle collector uses the new hook type. Simpler than a full dep graph.

**Option 4c — `lunar component get-json --git-sha $CURRENT_SHA`.**

Make the pulling collector always request the specific commit's JSON and block/retry if it's not there yet. Existing CLI already supports `--git-sha`. Doesn't require any hub changes, just a retry loop in the collector. Cheap but fragile (needs a timeout policy).

**Option 4d — Commit-scoped "bundle" as a first-class concept.**

At policy-run time, the hub assembles a per-commit bundle of *all* relevant component JSONs across the monorepo and makes them available to the running policy (not collector). Policy authors can then cross-reference without collectors having to pre-merge data. This is closest to the "bundled release record" framing but requires the biggest surface-area change.

**Recommendation:** start with **4c** (works today) → move to **4b** (staged phases) for production-grade monorepo use → eventually **4d** if cross-component analysis becomes a core use case.

---

## Adjacent bugs exposed by the test environment

### Dashboard SQL join mismatch (hotfix applied)

The `Components listing` dashboard's `All Components` panel has two SQL queries joined via `joinByField(idx)`:

- `score_history.sql` (refId A) enumerates components from `hub.components WHERE deleted = 0` → 16 rows on pantalasa.
- `listing.sql` (refId B) enumerates from `grafana.components` (which filters via `components_latest` → requires a git_sha) → 13 rows.

When the sets don't match, Grafana's `timeSeriesTable` transform crashes on `.trim()` of undefined for the mismatched series. Our three subdir components created the mismatch (they're in `hub.components` but never got into `components_latest`), breaking the dashboard on the pantalasa demo env.

**Hotfix applied directly to pantalasa Grafana:** updated `score_history.sql` to enumerate from `grafana.components WHERE pr IS NULL` so both queries use the same set. `decnmi0dtoef4a` is now at v2 on `lunar.demo.earthly.dev`.

**Proper fix:** PR against `earthly/lunar` modifying [`lunar/grafana/sql/components/score_history.sql`](lunar/grafana/sql/components/score_history.sql) with the same change. Will roll out via the normal dashboard build + ansible deploy. Cronos needs the same hotfix applied (creds weren't in `AGENTS.md` — stale).

### Asymmetric check materialization for subdir components

Only `services/api-python` got check rows after the push; `services/backend-go` and `compliance` didn't, despite identical tag sets and filter conditions. Root cause not fully determined but likely involves the `MatchStar` filter interacting with some ordering or dedup stage non-deterministically. This is subtle and hard to reproduce reliably — worth investigating separately.

### Auto-cataloged components collide with declared subdir components

The `github-org` cataloger runs every 5 minutes on pantalasa and auto-creates `github.com/pantalasa/<reponame>` for every repo in the org. When we added a monorepo with subdir components declared in lunar-config, the bare repo name got auto-created in the `other` domain too. Fix: declare the bare repo as a component in your intended domain so the cataloger's entry merges into it instead of living separately. Docs should call this out explicitly.

### Stale Grafana credentials in `AGENTS.md`

The `lunar/910vfBf` combo in `earthly-agent-config/AGENTS.md` works on pantalasa (lunar.demo.earthly.dev) but NOT on cronos (cronos.demo.earthly.dev). Fix: update AGENTS.md to note the cronos creds are different, or retrieve the correct cronos creds from `group_vars/all/secrets.yml`.

---

## Recommended execution order

1. **Fix the webhook filter (Axis 2a)** — single-function change in `filter.go`, unblocks code-collector fanout for subdir components. Includes a small test.
2. **Fix the cron `ParseOwnerRepo` bug** — one-line change, use `fetch.ParseComponentName` instead. Includes a test.
3. **Add `LUNAR_COMPONENT_REPO_ROOT` env var** to the executor (always populated; no behavioral change for non-subdir components).
4. **Implement `scope: subdir` hook flag (Axis 3a)** behind an opt-in so we can migrate stock collectors incrementally.
5. **Land the dashboard SQL fix** (Axis 4 dashboard section above) as a lunar PR.
6. **First-class `path:` field on components (Axis 1a)** — schema migration + fetcher changes + store changes. Moderate size but bounded.
7. **Migrate stock collectors to `scope: subdir`**: start with `readme`, `codeowners`, `docker`, `k8s`, `terraform`, `syft`, `trivy` — they all make more sense at subdir scope for subdir components.
8. **Implement `lunar.yml` for per-subdir config** (Axis 1 follow-up). Good monorepo UX; lower priority than the correctness fixes.
9. **Design the ordering primitive (Axis 4)** once collector behavior is solid — start with 4c (retry loop in the pulling collector), then evaluate 4b.

Fixes 1-3 together should unblock most of the realistic monorepo story on the existing demo envs. They're also the smallest and safest patches.

---

## CI-collector specifics (briefer)

CI collectors add one extra wrinkle on top of everything above: CI events fire per *pipeline run*, not per component. One CI workflow can build multiple services in a monorepo, and there's no clean way today to attribute `docker build` events to one component vs another within the same run.

Options worth exploring after the code-collector substrate is solid:

- **Hook-level `path:` scoping** — a new `path:` field on CI hooks that fires only when the traced command's cwd matches. The CI observer already knows each process's `Process.Dir` ([`lunar/trace/events/events_linux.go`](lunar/trace/events/events_linux.go)) so this is a small addition to the match logic.
- **Output fan-out** — let a CI collector emit `lunar collect --component <id>` writes that target a different component than the one the CI run was associated with. Needed for cases like "monorepo build workflow produces SBOMs for each service and wants each one to land on the right component."
- **Matrix / affected-packages awareness** — integrate with `nx affected`, `turbo build --filter`, etc. to know which services a given CI run actually touched.

These need the component/path first-class model (Axis 1) before they can be designed cleanly. Deferring until the substrate is solid.

---

## Open questions

- **Is the asymmetric behavior we saw (only api-python got checks) deterministic or a race?** Worth a targeted reproduction with detailed logging to understand whether the `MatchStar` filter is actually as strict as the code reads, or whether there's a code path we haven't found that bypasses it.
- **Should `lunar.yml` complement or replace central component declaration?** Product-level question for monorepo teams — would a team rather declare all 30 services in one central file or 30 `lunar.yml` files next to each service?
- **How does the catalog reconcile per-subdir `lunar.yml` with central `lunar-config.yml`?** If both declare `github.com/org/mono/svc-a`, who wins? The docs say "lunar-config.yml takes precedence for scalars, arrays merge" — but that needs to be verified against a real implementation.
- **What's the right `scope: subdir` default?** Opt-in is safer but means existing stock collectors stay broken for monorepos until migrated. Opt-out is cleaner but breaks non-monorepo use of those same collectors where repo-root access is actually intended.

---

## Appendix: verified file references

Code-level citations (for authors of the actual fix PRs):

- Name parser: [`lunar/snippets/fetch/componentname.go`](lunar/snippets/fetch/componentname.go) — `ParseComponentName`, `ComponentName{Source, Org, Repo, Subdir}`
- Local component struct (no Subdir): [`lunar/snippets/fetch/fetch.go:111-120`](lunar/snippets/fetch/fetch.go)
- Store component row (no subdir column): [`lunar/hub/store/components.go:30-45`](lunar/hub/store/components.go)
- Webhook/push filter: [`lunar/hub/filter/filter.go:239-273`](lunar/hub/filter/filter.go), `filterComponents`
- `MatchStar`: [`lunar/util/str/str.go:13-19`](lunar/util/str/str.go)
- `ParseOwnerRepo` (cron collector bug): [`lunar/util/git/uri.go:35-44`](lunar/util/git/uri.go)
- Code-collector `workDir` construction: [`lunar/hub/collect/collect.go:137-140`](lunar/hub/collect/collect.go)
- Code-collector executor: [`lunar/hub/collect/executor.go:157-275`](lunar/hub/collect/executor.go)
- Snippet executor (engine `Dir`): [`lunar/snippets/executor.go:155-256`](lunar/snippets/executor.go)
- Cron-collector worker: [`lunar/hub/queue/workers/croncollect/worker.go:133-250`](lunar/hub/queue/workers/croncollect/worker.go)
- `SyncComponentRepo` (works correctly): [`lunar/hub/gitsync/github.go:123-154`](lunar/hub/gitsync/github.go)
- CI observer matching components: [`lunar/ci/observe.go:819-874`](lunar/ci/observe.go)
- Dashboard panel source: [`lunar/grafana/dashboards/components.json:300-460`](lunar/grafana/dashboards/components.json)
- Broken SQL: [`lunar/grafana/sql/components/score_history.sql`](lunar/grafana/sql/components/score_history.sql) (vs [`lunar/grafana/sql/components/listing.sql`](lunar/grafana/sql/components/listing.sql))
- Test-env collector (reference pattern): [`pantalasa/lunar collectors/terraform-internal/main.sh`](https://github.com/pantalasa/lunar/blob/main/collectors/terraform-internal/main.sh)
- Our test-env `release-bundle` collector: `pantalasa/lunar/collectors/release-bundle/` and `pantalasa-cronos/lunar/collectors/release-bundle/` (same source)
