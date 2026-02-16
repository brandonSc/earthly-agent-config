# Node.js Plugin Implementation Plan

## Overview

Port the Node.js language collector and create a Node.js policy for lunar-lib. Modeled after the Go collector (`lunar-lib/collectors/golang/`) which is the reference implementation.

**Prototype location:** `pantalasa-cronos/lunar/collectors/nodejs/`

**Important:** The Go collector's CI sub-collectors use `jq` in native mode. This is an existing inconsistency with the updated guide. New language CI sub-collectors should follow the updated guide: **native-bash, no `jq`, use `lunar collect` with individual fields.**

---

## Collector: `nodejs`

Directory: `lunar-lib/collectors/nodejs/`

### Sub-collectors

| Sub-collector | Hook | Image | Description |
|---------------|------|-------|-------------|
| `project` | `code` | `base-main` | Detect Node.js project structure, package manager, version, tooling config |
| `dependencies` | `code` | `base-main` | Parse `package.json` for dependencies |
| `cicd` | `ci-before-command` | `native` | Record npm/yarn/pnpm commands run in CI |
| `test-coverage` | `ci-after-command` | `native` | Extract coverage after test runs |

### Component JSON Paths

All data writes to `.lang.nodejs.*`:

| Path | Type | Sub-collector | Description |
|------|------|--------------|-------------|
| `.lang.nodejs.version` | string | project | Node.js version (e.g. `"20.11.0"`) |
| `.lang.nodejs.build_systems` | array | project | `["npm"]`, `["yarn"]`, `["pnpm"]` |
| `.lang.nodejs.source` | object | project | `{tool: "node", integration: "code"}` |
| `.lang.nodejs.native.package_json` | object | project | `{exists: true/false}` |
| `.lang.nodejs.native.package_lock` | object | project | `{exists: true/false}` |
| `.lang.nodejs.native.yarn_lock` | object | project | `{exists: true/false}` |
| `.lang.nodejs.native.pnpm_lock` | object | project | `{exists: true/false}` |
| `.lang.nodejs.native.tsconfig` | object | project | `{exists: true/false}` (TypeScript) |
| `.lang.nodejs.native.eslint_configured` | boolean | project | ESLint config detected |
| `.lang.nodejs.native.prettier_configured` | boolean | project | Prettier config detected |
| `.lang.nodejs.native.engines_node` | string | project | `engines.node` from package.json (e.g. `">=18"`) |
| `.lang.nodejs.native.monorepo` | object | project | `{type: "workspaces"/"turborepo"/"nx"/"lerna"}` or absent |
| `.lang.nodejs.dependencies.direct[]` | array | dependencies | From `dependencies` in package.json |
| `.lang.nodejs.dependencies.dev[]` | array | dependencies | From `devDependencies` in package.json |
| `.lang.nodejs.dependencies.source` | object | dependencies | `{tool: "npm", integration: "code"}` |
| `.lang.nodejs.cicd.cmds[]` | array | cicd | `{cmd, version}` |
| `.lang.nodejs.cicd.source` | object | cicd | `{tool: "node", integration: "ci"}` |
| `.lang.nodejs.tests.coverage` | object | test-coverage | `{percentage, source: {tool, integration: "ci"}}` |
| `.testing.coverage` | object | test-coverage | Normalized coverage (dual-write) |
| `.testing.source` | object | test-coverage | `{tool: "jest"/"vitest"/"nyc", integration: "ci"}` |

### Key Implementation Notes

**`project.sh` (code hook):**
- Detect via `package.json` existence (primary signal)
- Use `helpers.sh` with an `is_nodejs_project` function
- Detect package manager: npm (package-lock.json), yarn (yarn.lock), pnpm (pnpm-lock.yaml)
- Get Node.js version from container: `node -v | sed 's/^v//'`
- Detect TypeScript: `tsconfig.json` or `tsconfig.*.json`
- Detect ESLint: `.eslintrc`, `.eslintrc.*`, `eslint.config.*`, or `eslintConfig` in package.json
- Detect Prettier: `.prettierrc`, `.prettierrc.*`, `prettier.config.*`, or `prettier` in package.json
- Extract `engines.node` from package.json (if present)
- Detect monorepo: `workspaces` in package.json, `turbo.json`, `nx.json`, `lerna.json`
- Write to `.lang.nodejs` — MUST be written for policy detection
- Use `categories: ["languages", "build"]` in landing page (matching Go collector)

**`dependencies.sh` (code hook):**
- Parse `package.json` using `jq` (available in container)
- Extract `dependencies` as `direct[]`, `devDependencies` as `dev[]`
- Version strings are ranges (e.g. `^1.2.3`) — collect as-is
- Write to `.lang.nodejs.dependencies`

**`cicd.sh` (ci-before-command, `native`):**
- Pattern: `.*\b(npm|npx|yarn|pnpm)\b.*`
- **MUST be native-bash** — no `jq`
- Get version: `node -v 2>/dev/null | sed 's/^v//'`
- Use `lunar collect` with individual fields

**`test-coverage.sh` (ci-after-command, `native`):**
- Pattern: `.*\b(npm\s+test|npx\s+jest|npx\s+vitest|yarn\s+test|pnpm\s+test)\b.*`
- Look for coverage output in known locations: `coverage/coverage-summary.json`
- Parse JSON with native grep: extract `total.lines.pct` or `total.statements.pct`
- **Do NOT run the test suite** — the prototype incorrectly runs `npx jest --coverage`. The test already ran (that's what triggered the hook). Only read existing coverage output.
- Write to BOTH `.lang.nodejs.tests.coverage` AND `.testing.coverage` (dual-write)
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
4. **`test-coverage.sh` runs `npx jest --coverage`** — WRONG. Must read existing coverage output, not re-run tests.
5. **No `source` metadata** — add consistently
6. **Missing TypeScript detection** — add `tsconfig.json`
7. **Missing ESLint/Prettier detection** — add config file checks
8. **Missing `engines.node` extraction** — add from package.json
9. **Missing monorepo detection** — add workspaces/turbo/nx/lerna
10. **No dual-write to `.testing`** — test-coverage must write to both paths

---

## Policy: `nodejs`

Directory: `lunar-lib/policies/nodejs/`

### Checks

| Check | What it does | Input |
|-------|-------------|-------|
| `lockfile-exists` | Ensures a lockfile exists (any of package-lock, yarn.lock, pnpm-lock) | — |
| `typescript-configured` | Ensures TypeScript is configured (`tsconfig.json` exists) | — |
| `engines-pinned` | Ensures `engines.node` is set in package.json | — |
| `min-node-version` | Ensures Node.js version meets minimum | `min_node_version` (default `"18"`) |
| `min-node-version-cicd` | Ensures Node.js version in CI meets minimum | `min_node_version_cicd` (default `"18"`) |

### Policy Implementation Notes

- All checks should verify `.lang.nodejs` exists first, skip if not a Node project
- `lockfile-exists`: Check any of `.lang.nodejs.native.package_lock.exists`, `.lang.nodejs.native.yarn_lock.exists`, `.lang.nodejs.native.pnpm_lock.exists`
- `typescript-configured`: Check `.lang.nodejs.native.tsconfig.exists`
- `engines-pinned`: Check `.lang.nodejs.native.engines_node` is not null/empty
- `min-node-version`: Compare `.lang.nodejs.version` against threshold
- `min-node-version-cicd`: Check `.lang.nodejs.cicd.cmds[].version` against threshold

---

## Implementation Steps

1. Create worktree `lunar-lib-wt-nodejs` on branch `brandon/nodejs`
2. Read `lunar-lib/collectors/golang/` as the reference
3. Implement the `nodejs` collector (4 sub-collectors)
4. Implement the `nodejs` policy (5 checks)
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
# Collector (test on multiple components)
lunar collector dev nodejs.project --component github.com/pantalasa-cronos/frontend
lunar collector dev nodejs.project --component github.com/pantalasa-cronos/sendgrid-nodejs
lunar collector dev nodejs.project --component github.com/pantalasa-cronos/backend
lunar collector dev nodejs.dependencies --component github.com/pantalasa-cronos/frontend

# Policy
lunar policy dev nodejs.lockfile-exists --component github.com/pantalasa-cronos/frontend
lunar policy dev nodejs.typescript-configured --component github.com/pantalasa-cronos/frontend
lunar policy dev nodejs.engines-pinned --component github.com/pantalasa-cronos/frontend
lunar policy dev nodejs.min-node-version --component github.com/pantalasa-cronos/frontend
lunar policy dev nodejs.lockfile-exists --component github.com/pantalasa-cronos/backend
```

### Expected Results (pantalasa-cronos)

| Component | project | lockfile-exists | typescript-configured | engines-pinned | min-node-version |
|-----------|---------|----------------|----------------------|---------------|-----------------|
| frontend (Node) | PASS | Verify lockfile type | Verify tsconfig | Verify engines field | PASS if >= 18 |
| sendgrid-nodejs (Node) | PASS | Verify | Verify | Verify | Verify |
| evergreen (Node) | PASS | Verify | Verify | Verify | Verify |
| backend (Go) | exits cleanly | SKIP | SKIP | SKIP | SKIP |
| auth (Python) | exits cleanly | SKIP | SKIP | SKIP | SKIP |

*These are draft expected results — verify and adjust before handing off.*

### Edge Cases to Test

1. **Component with no `package.json`** — Collector exits cleanly, all policies skip
2. **Node project with no lockfile** — `lockfile-exists` should FAIL
3. **Node project with `yarn.lock` but no `package-lock.json`** — `lockfile-exists` should PASS
4. **Node project without TypeScript** — `typescript-configured` should FAIL (not skip — the project IS Node.js, it just doesn't have TS)
5. **Node project without `engines.node`** — `engines-pinned` should FAIL
