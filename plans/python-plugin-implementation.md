# Python Plugin Implementation Plan

## Overview

Port the Python language collector and create a Python policy for lunar-lib. Modeled after the Go collector (`lunar-lib/collectors/golang/`) which is the reference implementation.

**Prototype location:** `pantalasa-cronos/lunar/collectors/python/`

---

## Collector: `python`

Directory: `lunar-lib/collectors/python/`

### Sub-collectors

| Sub-collector | Hook | Image | Description |
|---------------|------|-------|-------------|
| `project` | `code` | `base-main` | Detect Python project structure, build tools, version |
| `dependencies` | `code` | `base-main` | Parse `requirements.txt` / `pyproject.toml` for dependencies |
| `cicd` | `ci-before-command` | `native` | Record Python/pip commands run in CI |
| `test-coverage` | `ci-after-command` | `native` | Extract coverage from `coverage.xml` after test runs |

### Component JSON Paths

All data writes to `.lang.python.*`:

| Path | Type | Sub-collector | Description |
|------|------|--------------|-------------|
| `.lang.python.version` | string | project | Python version (e.g. `"3.12.1"`) |
| `.lang.python.build_systems` | array | project | `["pip"]`, `["poetry"]`, `["pipenv"]`, etc. |
| `.lang.python.source` | object | project | `{tool: "python", integration: "code"}` |
| `.lang.python.native.pyproject` | object | project | `{exists: true/false}` |
| `.lang.python.native.requirements_txt` | object | project | `{exists: true/false}` |
| `.lang.python.native.setup_py` | object | project | `{exists: true/false}` |
| `.lang.python.native.pipfile` | object | project | `{exists: true/false}` |
| `.lang.python.dependencies.direct[]` | array | dependencies | `{path, version, indirect: false}` |
| `.lang.python.dependencies.transitive[]` | array | dependencies | (empty for now — pip doesn't easily resolve transitives) |
| `.lang.python.dependencies.source` | object | dependencies | `{tool: "pip", integration: "code"}` |
| `.lang.python.cicd.cmds[]` | array | cicd | `{cmd, version}` |
| `.lang.python.cicd.source` | object | cicd | `{tool: "python", integration: "ci"}` |
| `.lang.python.tests.coverage` | object | test-coverage | `{percentage, source: {tool: "coverage", integration: "ci"}}` |
| `.testing.coverage` | object | test-coverage | Normalized coverage (same as Go pattern) |
| `.testing.source` | object | test-coverage | `{tool: "pytest", integration: "ci"}` |

### Key Implementation Notes

**`project.sh` (code hook):**
- Detect via `*.py` files or `pyproject.toml` / `requirements.txt` / `setup.py` / `Pipfile`
- Use `helpers.sh` with an `is_python_project` function (same pattern as Go's `is_go_project`)
- Detect build systems: pip, poetry, hatch, setuptools, pipenv
- Get Python version from container's python3 (the base image has Python)
- Write to `.lang.python` — this MUST be written even if minimal, so policies can detect "this is a Python project"

**`dependencies.sh` (code hook):**
- Parse `requirements.txt` (line-by-line, handle `==` version pinning)
- Parse `pyproject.toml` dependencies if present (the prototype doesn't do this yet — consider using Python's `tomllib` in the container)
- Write to `.lang.python.dependencies`

**`cicd.sh` (ci-before-command, `native`):**
- Pattern: `.*\b(python|python3|pip|pip3)\b.*`
- **MUST be native-bash** — no `jq`. Use `lunar collect` with individual fields
- Get version: `python3 --version 2>/dev/null | awk '{print $2}'`
- Collect command string and version

**`test-coverage.sh` (ci-after-command, `native`):**
- Pattern: `.*\b(pytest|python.*-m.*pytest|python.*test)\b.*`
- Look for `coverage.xml` (pytest-cov output)
- Extract coverage using native bash XML parsing or simple grep (no Python/jq available in native)
- Write to `.lang.python.tests.coverage` AND `.testing.coverage`
- Also write `.testing.source` to signal tests were executed

### Files

| File | Purpose |
|------|---------|
| `lunar-collector.yml` | Manifest |
| `project.sh` | Project detection (code hook) |
| `dependencies.sh` | Dependency parsing (code hook) |
| `cicd.sh` | CI command recording (native, ci-before-command) |
| `test-coverage.sh` | Coverage extraction (native, ci-after-command) |
| `helpers.sh` | `is_python_project` function |
| `README.md` | Documentation |
| `assets/python.svg` | Icon |

### Differences from Prototype

The pantalasa prototype has issues that must be fixed:

1. **CI collectors use `jq`** — must be rewritten as native-bash since they run `native`
2. **CI collectors use `default_image: earthly/lunar-lib:base-main`** — should be `native` for CI hooks
3. **`install.sh` exists** — should be removed (legacy pattern)
4. **No cleanup needed in code collectors** — container is disposable
5. **No `source` metadata** on some paths — follow Go pattern of always including `source: {tool, integration}`
6. **`test-coverage.sh` uses Python** — needs native-bash rewrite for CI context (or keep Python only if using container image)

---

## Policy: `python`

Directory: `lunar-lib/policies/python/`

### Checks

| Check | What it does | Input |
|-------|-------------|-------|
| `pyproject-exists` | Ensures `pyproject.toml` exists (modern Python standard) | — |
| `requirements-pinned` | Ensures dependencies use pinned versions (`==`), not ranges | — |
| `min-python-version` | Ensures Python version meets minimum | `min_python_version` (default `"3.9"`) |
| `min-python-version-cicd` | Ensures Python version in CI meets minimum | `min_python_version_cicd` (default `"3.9"`) |

### Policy Implementation Notes

- All checks should first verify `.lang.python` exists, skip if not a Python project
- `pyproject-exists`: Check `.lang.python.native.pyproject.exists`
- `requirements-pinned`: Iterate `.lang.python.dependencies.direct[]`, check each has a non-empty `version`
- `min-python-version`: Compare `.lang.python.version` against threshold (semver comparison)
- `min-python-version-cicd`: Check `.lang.python.cicd.cmds[].version` against threshold

---

## Implementation Steps

1. Create worktree `lunar-lib-wt-python` on branch `brandon/python`
2. Read `lunar-lib/collectors/golang/` as the reference — follow the same patterns
3. Implement the `python` collector (4 sub-collectors)
4. Implement the `python` policy (4 checks)
5. Test using `lunar dev` commands against pantalasa-cronos components
6. Complete the pre-push checklist (see LUNAR-PLUGIN-GUIDE.md)
7. Create draft PR

---

## Testing

### Local Dev Testing

```yaml
# In pantalasa-cronos/lunar/lunar-config.yml
collectors:
  - uses: ../lunar-lib-wt-python/collectors/python
    on: ["domain:engineering"]

policies:
  - uses: ../lunar-lib-wt-python/policies/python
    name: python
    initiative: good-practices
    enforcement: report-pr
    with:
      min_python_version: "3.9"
```

```bash
# Collector
lunar collector dev python.project --component github.com/pantalasa-cronos/auth
lunar collector dev python.project --component github.com/pantalasa-cronos/backend
lunar collector dev python.dependencies --component github.com/pantalasa-cronos/auth

# Policy
lunar policy dev python.pyproject-exists --component github.com/pantalasa-cronos/auth
lunar policy dev python.min-python-version --component github.com/pantalasa-cronos/auth
lunar policy dev python.pyproject-exists --component github.com/pantalasa-cronos/backend
```

### Expected Results (pantalasa-cronos)

| Component | project | dependencies | pyproject-exists | min-python-version |
|-----------|---------|-------------|-----------------|-------------------|
| auth (Python) | PASS (detects Python) | PASS (has requirements.txt) | Verify if pyproject.toml exists | PASS if >= 3.9 |
| backend (Go) | exits cleanly (no Python) | exits cleanly | SKIP (not Python) | SKIP (not Python) |
| frontend (Node) | exits cleanly (no Python) | exits cleanly | SKIP (not Python) | SKIP (not Python) |

*These are draft expected results — verify and adjust before handing off.*

### Edge Cases to Test

1. **Component with no Python files** — Collector exits cleanly, all policies skip
2. **Python project with no `requirements.txt`** — `dependencies` sub-collector exits cleanly, `requirements-pinned` skips
3. **Dependencies without version pins** (e.g. `requests` instead of `requests==2.31.0`) — `requirements-pinned` should FAIL
