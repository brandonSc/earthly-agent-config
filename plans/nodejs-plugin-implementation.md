# Node.js Plugin Implementation Plan

## Overview

Port the Node.js language collector and create a Node.js policy for lunar-lib. Modeled after the Go collector (`lunar-lib/collectors/golang/`) which is the reference implementation.

**Prototype location:** `pantalasa-cronos/lunar/collectors/nodejs/`

---

## Collector: `nodejs`

Directory: `lunar-lib/collectors/nodejs/`

### Sub-collectors

| Sub-collector | Hook | Image | Description |
|---------------|------|-------|-------------|
| `project` | `code` | `base-main` | Detect Node.js project structure, package manager, version |
| `dependencies` | `code` | `base-main` | Parse `package.json` for dependencies |
| `cicd` | `ci-before-command` | `native` | Record npm/yarn/pnpm commands run in CI |
| `test-coverage` | `ci-after-command` | `native` | Extract coverage after Jest/Vitest/nyc test runs |

### Component JSON Paths

All data writes to `.lang.nodejs.*`:

| Path | Type | Sub-collector | Description |
|------|------|--------------|-------------|
| `.lang.nodejs.version` | string | project | Node.js version (e.g. `"20.11.0"`) |
| `.lang.nodejs.build_systems` | array | project | `["npm"]`, `["yarn"]`, `["pnpm"]`, etc. |
| `.lang.nodejs.source` | object | project | `{tool: "node", integration: "code"}` |
| `.lang.nodejs.native.package_json` | object | project | `{exists: true/false}` |
| `.lang.nodejs.native.package_lock` | object | project | `{exists: true/false}` |
| `.lang.nodejs.native.yarn_lock` | object | project | `{exists: true/false}` |
| `.lang.nodejs.native.pnpm_lock` | object | project | `{exists: true/false}` |
| `.lang.nodejs.dependencies.direct[]` | array | dependencies | `{path, version, indirect: false}` |
| `.lang.nodejs.dependencies.dev[]` | array | dependencies | Dev dependencies from `devDependencies` |
| `.lang.nodejs.dependencies.source` | object | dependencies | `{tool: "npm", integration: "code"}` |
| `.lang.nodejs.cicd.cmds[]` | array | cicd | `{cmd, version}` |
| `.lang.nodejs.cicd.source` | object | cicd | `{tool: "node", integration: "ci"}` |
| `.lang.nodejs.tests.coverage` | object | test-coverage | `{percentage, source: {tool, integration: "ci"}}` |
| `.testing.coverage` | object | test-coverage | Normalized coverage |
| `.testing.source` | object | test-coverage | `{tool: "jest"/"vitest"/"nyc", integration: "ci"}` |

### Key Implementation Notes

**`project.sh` (code hook):**
- Detect via `package.json` existence (primary signal)
- Use `helpers.sh` with an `is_nodejs_project` function
- Detect package manager: npm (package-lock.json), yarn (yarn.lock), pnpm (pnpm-lock.yaml)
- Get Node.js version from container: `node -v | sed 's/^v//'`
- Write to `.lang.nodejs` — MUST be written for policy detection

**`dependencies.sh` (code hook):**
- Parse `package.json` using `jq` (available in container)
- Extract both `dependencies` and `devDependencies`
- Write `direct[]` from `dependencies`, `dev[]` from `devDependencies`
- Version strings from package.json are ranges (e.g. `^1.2.3`) — collect as-is

**`cicd.sh` (ci-before-command, `native`):**
- Pattern: `.*\b(npm|npx|yarn|pnpm)\b.*`
- **MUST be native-bash** — no `jq`
- Get version: `node -v 2>/dev/null | sed 's/^v//'`
- Collect command and version using `lunar collect` with individual fields

**`test-coverage.sh` (ci-after-command, `native`):**
- Pattern: `.*\b(npm\s+test|npx\s+jest|npx\s+vitest|yarn\s+test|pnpm\s+test)\b.*`
- Look for coverage output in known locations:
  - Jest: `coverage/coverage-summary.json`
  - Vitest: `coverage/coverage-summary.json`
  - nyc/istanbul: `coverage/coverage-summary.json` or `.nyc_output/`
- Parse coverage-summary.json with simple grep/awk if possible (native bash)
- Write to `.lang.nodejs.tests.coverage` AND `.testing.coverage`
- Also write `.testing.source` to signal tests were executed

### Files

| File | Purpose |
|------|---------|
| `lunar-collector.yml` | Manifest |
| `project.sh` | Project detection (code hook) |
| `dependencies.sh` | Dependency parsing (code hook) |
| `cicd.sh` | CI command recording (native, ci-before-command) |
| `test-coverage.sh` | Coverage extraction (native, ci-after-command) |
| `helpers.sh` | `is_nodejs_project` function |
| `README.md` | Documentation |
| `assets/nodejs.svg` | Icon |

### Differences from Prototype

1. **CI collectors use `jq`** — must be rewritten as native-bash
2. **CI collectors use container image** — should be `native`
3. **`install.sh` exists** — remove
4. **`test-coverage.sh` runs `npx jest --coverage`** — this is wrong for a CI collector. It should *detect* existing coverage output, not *run* the test suite. The test suite already ran (that's what triggered the hook). Look for the coverage report file instead.
5. **No `source` metadata** — add consistently

---

## Policy: `nodejs`

Directory: `lunar-lib/policies/nodejs/`

### Checks

| Check | What it does | Input |
|-------|-------------|-------|
| `lockfile-exists` | Ensures a lockfile exists (package-lock.json, yarn.lock, or pnpm-lock.yaml) | — |
| `min-node-version` | Ensures Node.js version meets minimum | `min_node_version` (default `"18"`) |
| `min-node-version-cicd` | Ensures Node.js version in CI meets minimum | `min_node_version_cicd` (default `"18"`) |
| `no-deprecated-deps` | Warns if `package.json` has dependencies known to be deprecated | — (future, skip for now) |

**Note:** `no-deprecated-deps` is aspirational. If too complex for v1, skip it and just implement the first 3 checks.

### Policy Implementation Notes

- All checks should verify `.lang.nodejs` exists first, skip if not a Node project
- `lockfile-exists`: Check `.lang.nodejs.native.package_lock.exists` OR `.lang.nodejs.native.yarn_lock.exists` OR `.lang.nodejs.native.pnpm_lock.exists`
- `min-node-version`: Compare `.lang.nodejs.version` against threshold
- `min-node-version-cicd`: Check `.lang.nodejs.cicd.cmds[].version` against threshold

---

## Implementation Steps

1. Create worktree `lunar-lib-wt-nodejs` on branch `brandon/nodejs`
2. Read `lunar-lib/collectors/golang/` as the reference
3. Implement the `nodejs` collector (4 sub-collectors)
4. Implement the `nodejs` policy (3 checks minimum)
5. Test using `lunar dev` commands against pantalasa-cronos components
6. Complete the pre-push checklist
7. Create draft PR

---

## Testing

### Local Dev Testing

```yaml
# In pantalasa-cronos/lunar/lunar-config.yml
collectors:
  - uses: ../lunar-lib-wt-nodejs/collectors/nodejs
    on: ["domain:engineering"]

policies:
  - uses: ../lunar-lib-wt-nodejs/policies/nodejs
    name: nodejs
    initiative: good-practices
    enforcement: report-pr
    with:
      min_node_version: "18"
```

```bash
# Collector
lunar collector dev nodejs.project --component github.com/pantalasa-cronos/frontend
lunar collector dev nodejs.project --component github.com/pantalasa-cronos/backend
lunar collector dev nodejs.dependencies --component github.com/pantalasa-cronos/frontend

# Policy
lunar policy dev nodejs.lockfile-exists --component github.com/pantalasa-cronos/frontend
lunar policy dev nodejs.min-node-version --component github.com/pantalasa-cronos/frontend
lunar policy dev nodejs.lockfile-exists --component github.com/pantalasa-cronos/backend
```

### Expected Results (pantalasa-cronos)

| Component | project | dependencies | lockfile-exists | min-node-version |
|-----------|---------|-------------|----------------|-----------------|
| frontend (Node) | PASS (detects Node) | PASS (has package.json) | PASS (verify lockfile type) | PASS if >= 18 |
| sendgrid-nodejs (Node) | PASS (detects Node) | PASS | Verify lockfile | Verify version |
| backend (Go) | exits cleanly (no Node) | exits cleanly | SKIP (not Node) | SKIP (not Node) |
| auth (Python) | exits cleanly (no Node) | exits cleanly | SKIP (not Node) | SKIP (not Node) |

*These are draft expected results — verify and adjust before handing off.*

### Edge Cases to Test

1. **Component with no `package.json`** — Collector exits cleanly, all policies skip
2. **Node project with no lockfile** — `lockfile-exists` should FAIL
3. **Node project with `yarn.lock` but no `package-lock.json`** — `lockfile-exists` should still PASS (any lockfile is acceptable)
