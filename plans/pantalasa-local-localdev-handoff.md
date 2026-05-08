# Pantalasa-Local Localdev Handoff

**For an agent or future-me on the Linux dev box.** Everything below is the state as of 2026-05-08 after migrating localdev work off `pantalasa` and `pantalasa-cronos` onto a dedicated sandbox org.

## TL;DR

We created a new GitHub org **`pantalasa-local`** that mirrors a 13-repo subset of `pantalasa` (default branch only). The Lunar localdev stack now defaults to it. A new 1Password item holds the GitHub PAT used by localdev. There's an open PR on `earthly/lunar` to wire the new defaults into the Earthfile — that PR needs an end-to-end verification on the Linux box before merging.

## What's in `pantalasa-local`

- 13 repos mirrored from `pantalasa/*` on 2026-05-08, default branch only (no `localdev-*` history carried over).
- Same visibility as the source repos (3 private: `lunar`, `auth`, `inventory`; 10 public).
- `whoami` keeps its `master` default branch; everything else is `main`.
- Org plan: **free tier** — no SAML SSO enforcement, so PATs don't need separate SSO authorization.
- Bender App (`me-bender`) install: confirm with `gh api /orgs/pantalasa-local/installations --jq '.installations[].app_slug'`. If not yet installed, see "Bender install" below.

| Repo | Default branch | Visibility |
|------|----------------|------------|
| lunar | main | private |
| backend | main | public |
| frontend | main | public |
| auth | main | private |
| whoami | master | public |
| http-echo | main | public |
| spring-petclinic | main | public |
| inventory | main | private |
| rust-service | main | public |
| transactions-s3 | main | public |
| dotnet-service | main | public |
| compliance-docs | main | public |
| internal-devbox | main | public |

## Manifest (`pantalasa-local/lunar@main`)

Already pushed. Differences from `pantalasa/lunar@main`:
- All `github.com/pantalasa/*` component URIs rewritten to `github.com/pantalasa-local/*`
- Catalogers `github-org` `org_name` = `pantalasa-local`
- `hub.host` set to `localhost` (no remote shared hub for this sandbox; localdev IS the hub)
- `terraform-internal` collector regex/component-id updated
- `.github/workflows/check-component.yml` workflow input default updated
- `README.md` rewritten to describe sandbox purpose
- `dashboards/release-history.json` and inline doc references updated

## Token

A new classic PAT was minted by Brandon and stored in 1Password:

- Item: **`lunar/localdev-pantalasa-local-token`**
- Vault: `cloud`
- Required scopes: `admin:org`, `repo`, `workflow`
- No SSO authorization needed (pantalasa-local is free tier)

The legacy item `lunar/localdev-github-token` is left untouched — Nacho's localdev (which still points at `pantalasa`) keeps working.

Verification command on the Linux box:

```bash
op item get lunar/localdev-pantalasa-local-token --reveal --vault cloud --fields password | head -c 8 && echo "..."
# expect ghp_xxx... or github_pat_xxx...
```

## Open PR on earthly/lunar

**PR**: https://github.com/earthly/lunar/pull/1482 (draft, base `main`)

**Branch**: `brandon/localdev-pantalasa-local-defaults`

**To check it out on the linux box:**

```bash
cd ~/code/earthly/lunar
git fetch origin brandon/localdev-pantalasa-local-defaults
git worktree add ../lunar-wt-localdev-defaults brandon/localdev-pantalasa-local-defaults
cd ../lunar-wt-localdev-defaults/localdev
```

**Diff** (on `localdev/Earthfile`):

```diff
-   ARG --required LUNAR_MANIFEST_URL
+   # Defaults to the pantalasa-local sandbox org with a per-user branch
+   # (localdev-<whoami>-main). Override via .arg, env, or
+   # --LUNAR_MANIFEST_URL=github://<org>/<repo>@<branch>.
+   ARG LUNAR_MANIFEST_URL=github://pantalasa-local/lunar@localdev-$(whoami)-main
    ...
-   ARG GITHUB_TOKEN=$(op item get lunar/localdev-github-token ...)
+   ARG GITHUB_TOKEN=$(op item get lunar/localdev-pantalasa-local-token ...)
```

Same change applied to `+create-custom-branch` (default URL is `github://pantalasa-local/lunar@main` for that target since it derives the branch from `$(whoami)` separately).

### What's tested

On Mac (parse + dry-run):

- ✓ `earthly ls` parses cleanly
- ✓ `earthly +localdev --GITHUB_TOKEN=__sentinel__` evaluates ARGs end-to-end. Confirmed:
    - `LUNAR_MANIFEST_URL` resolves to `github://pantalasa-local/lunar@localdev-<whoami>-main`
    - `LOCALDEV_LABEL` derives to `localdev-<whoami>-main` and passes the `localdev-*` prefix gate
    - The `op item get lunar/localdev-pantalasa-local-token` line is what executes (visible in earthly output)

Against `pantalasa-local` directly via `gh api`:

- ✓ `POST /orgs/pantalasa-local/actions/runners/registration-token` returns a token
- ✓ `GET /orgs/pantalasa-local/actions/runners` returns 0 (clean state)
- ✓ Webhook list/create allowed on both public (backend) and private (lunar) repos
- ✓ Manifest readable; branch ref create + delete on `pantalasa-local/lunar` works
- ✓ All 12 component repos exist and their default branches match what the manifest declares

### What still needs testing on the Linux box

**Important:** test from the PR branch, not from `main`. `main` does not have the new defaults yet.

```bash
cd ~/code/earthly/lunar
git fetch origin brandon/localdev-pantalasa-local-defaults
git worktree add ../lunar-wt-localdev-defaults brandon/localdev-pantalasa-local-defaults
cd ../lunar-wt-localdev-defaults/localdev
```

Then:

1. `op item get lunar/localdev-pantalasa-local-token --reveal --vault cloud --fields password | head -c 8 && echo "..."` — should print a token prefix (proves the 1Password item is reachable from `op` CLI in your environment).
2. `earthly +create-custom-branch` (no flags). Should iterate the 12 components + the manifest repo, creating `localdev-<whoami>-main` branches across them.
3. `earthly +localdev` (no flags). Brings up the kind/k8s stack:
    - registers a runner labeled `localdev-<whoami>-main` on pantalasa-local org
    - registers webhooks on each component repo (visible at `https://github.com/organizations/pantalasa-local/settings/hooks` and per-repo webhook page)
    - hub starts, ngrok URL resolves, agents come up
4. (Optional) push a commit to one of the `localdev-<whoami>-main` component branches and confirm the hub processes the webhook event.

**Note on the localdev refactor:** `+localdev` is now kind/Helm-based on `main` (was docker-compose at the time pantalasa-local was created). Make sure `kind` and `kubectl` are installed on the linux box and port 5000 is free. If you hit unrelated infra issues, those are separate from this PR — the PR only changes ARG defaults.

**Reporting back:** add a comment on https://github.com/earthly/lunar/pull/1482 with the result. If everything works, mark the PR ready for review. If something fails, the relevant logs + the comment will give context for fixing it.

### Verification commands

```bash
# Branch existence after +create-custom-branch
for r in lunar backend frontend auth whoami http-echo spring-petclinic inventory rust-service transactions-s3 dotnet-service compliance-docs internal-devbox; do
    branch="localdev-$(whoami)-main"
    [ "$r" = "whoami" ] && branch="localdev-$(whoami)-master"  # whoami uses master as base
    code=$(gh api -i "/repos/pantalasa-local/$r/branches/$branch" 2>&1 | head -1)
    printf "  %-30s %s\n" "$r" "$code"
done
```

```bash
# After +localdev: confirm runner registered
gh api /orgs/pantalasa-local/actions/runners --jq '.runners[] | "\(.name) \(.labels | map(.name) | join(","))"'
```

```bash
# After +localdev: confirm webhooks registered on a few repos
for r in lunar backend frontend; do
    echo "=== $r ==="
    gh api "/repos/pantalasa-local/$r/hooks" --jq '.[] | "\(.config.url) active=\(.active)"'
done
```

### Rollback

If the PR causes issues for someone else (e.g., Nacho), the rollback is just reverting the Earthfile changes. Anyone whose `.arg` already overrides `GITHUB_TOKEN` and/or `LUNAR_MANIFEST_URL` is unaffected by the default change — overrides take precedence.

## Bender install on pantalasa-local

If `gh api /orgs/pantalasa-local/installations` doesn't show `me-bender`, install via:

**https://github.com/apps/me-bender/installations/new/permissions?target_id=282653687**

Pick "All repositories". Once installed, on the Linux box where bender is running:

```bash
bender-gh-token pantalasa-local
# should print a fresh installation token (not error)
```

## Related committed changes

`earthly-agent-config@main`:
- `AGENTS.md` — added pantalasa-local to repo layout table
- `LUNAR-CORE-GUIDE.md` — localdev setup section now references pantalasa-local + new 1Password item, includes `+create-custom-branch` step
- `plans/pantalasa-local-localdev-handoff.md` — this doc

## Open questions / decisions deferred

- **Mirrored CI workflows reference secrets that don't exist on pantalasa-local** (`SNYK_TOKEN`, `CODECOV_TOKEN`, `DOCKERHUB_USERNAME`, etc.). CI will run but fail those steps. Lunar collectors that read workflow YAML (rather than results) are unaffected. Decide later whether to (a) copy secrets at the org level, (b) strip the broken steps from the mirrored workflows, or (c) leave them noisy.
- **External-service collectors** (`snyk`, `codecov`, `sonarqube`, `jira`, `pagerduty`, `gitleaks`, `codeql`, `license-origins`) are still in the manifest. They'll skip/error against pantalasa-local since their project keys / API tokens are scoped to pantalasa. Trim if noise is annoying.
- **Bender install on pantalasa-local** — link is in this doc; not auto-installed by anything.

## Quick reference

- Org URL: https://github.com/pantalasa-local
- Manifest: https://github.com/pantalasa-local/lunar
- Org settings (admin): https://github.com/organizations/pantalasa-local/settings/profile
- Org webhooks: https://github.com/organizations/pantalasa-local/settings/hooks
- Org runners: https://github.com/organizations/pantalasa-local/settings/actions/runners
- Bender install: https://github.com/apps/me-bender/installations/new/permissions?target_id=282653687
- 1Password item: `lunar/localdev-pantalasa-local-token` (vault: `cloud`)
