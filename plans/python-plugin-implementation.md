# Python Plugin Implementation Plan

## Overview

Port the Python language collector and create a Python policy for lunar-lib. Modeled after the Go collector (`lunar-lib/collectors/golang/`) which is the reference implementation.

**Prototype location:** `pantalasa-cronos/lunar/collectors/python/`

**Important:** The Go collector's CI sub-collectors (`cicd.sh`, `test-scope.sh`) use `jq` in native mode. This is an existing inconsistency with the updated guide. New language CI sub-collectors should follow the updated guide: **native-bash, no `jq`, use `lunar collect` with individual fields.**

---

## Collector: `python`

Directory: `lunar-lib/collectors/python/`

### Sub-collectors

| Sub-collector | Hook | Image | Description |
|---------------|------|-------|-------------|
| `project` | `code` | `base-main` | Detect Python project structure, build tools, version, linter/type-checker config |
| `dependencies` | `code` | `base-main` | Parse `requirements.txt` / `pyproject.toml` / `Pipfile` for dependencies |
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
| `.lang.python.native.poetry_lock` | object | project | `{exists: true/false}` |
| `.lang.python.native.pipfile_lock` | object | project | `{exists: true/false}` |
| `.lang.python.native.python_version_file` | object | project | `{exists: true/false}` (`.python-version` for pyenv) |
| `.lang.python.native.ruff_configured` | boolean | project | Ruff config detected in `pyproject.toml` or `.ruff.toml` |
| `.lang.python.native.mypy_configured` | boolean | project | mypy config detected |
| `.lang.python.native.linter` | string | project | Detected linter name (`"ruff"`, `"flake8"`, `"pylint"`, or `null`) |
| `.lang.python.dependencies.direct[]` | array | dependencies | `{path, version, indirect: false}` |
| `.lang.python.dependencies.transitive[]` | array | dependencies | (empty for now) |
| `.lang.python.dependencies.source` | object | dependencies | `{tool: "pip"/"poetry", integration: "code"}` |
| `.lang.python.cicd.cmds[]` | array | cicd | `{cmd, version}` |
| `.lang.python.cicd.source` | object | cicd | `{tool: "python", integration: "ci"}` |
| `.lang.python.tests.coverage` | object | test-coverage | `{percentage, source: {tool: "coverage", integration: "ci"}}` |
| `.testing.coverage` | object | test-coverage | Normalized coverage (same dual-write as Go) |
| `.testing.source` | object | test-coverage | `{tool: "pytest", integration: "ci"}` |

### Key Implementation Notes

**`project.sh` (code hook):**
- Detect via `*.py` files or `pyproject.toml` / `requirements.txt` / `setup.py` / `Pipfile`
- Use `helpers.sh` with an `is_python_project` function (same pattern as Go's `is_go_project`)
- Detect build systems: pip, poetry, hatch, setuptools, pipenv, uv
- Get Python version from container's python3 (the base image has Python)
- Detect lockfiles: `poetry.lock`, `Pipfile.lock`
- Detect `.python-version` (pyenv version pinning)
- Detect linter config: ruff (`.ruff.toml` or `[tool.ruff]` in pyproject.toml), flake8 (`.flake8`, `setup.cfg`), pylint (`.pylintrc`)
- Detect type checker: mypy (`mypy.ini`, `[tool.mypy]` in pyproject.toml), pyright (`pyrightconfig.json`)
- Write to `.lang.python` — this MUST be written even if minimal (per conventions: "Language Detection: Always Create the Object")
- Use `categories: ["languages", "build"]` in landing page (matching Go collector)

**`dependencies.sh` (code hook):**
- Parse `requirements.txt` (line-by-line, handle `==` version pinning)
- Parse `pyproject.toml` if present (use Python's `tomllib` in the container for `[project.dependencies]` or `[tool.poetry.dependencies]`)
- Parse `Pipfile` if present
- Write to `.lang.python.dependencies`

**`cicd.sh` (ci-before-command, `native`):**
- Pattern: `.*\b(python|python3|pip|pip3|poetry|pipenv|uv)\b.*`
- **MUST be native-bash** — no `jq`. Use `lunar collect` with individual fields
- Get version: `python3 --version 2>/dev/null | awk '{print $2}'`

**`test-coverage.sh` (ci-after-command, `native`):**
- Pattern: `.*\b(pytest|python.*-m.*pytest|python.*test)\b.*`
- Look for `coverage.xml` (pytest-cov output)
- Extract line-rate attribute using native grep: `grep -oP 'line-rate="\K[^"]+' coverage.xml`
- Multiply by 100 for percentage
- Write to BOTH `.lang.python.tests.coverage` AND `.testing.coverage` (dual-write pattern)
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
6. **Missing lockfile detection** — add poetry.lock, Pipfile.lock
7. **Missing linter/type-checker detection** — add ruff, flake8, mypy, pyright
8. **Missing `.python-version` detection** — add for pyenv support
9. **No dual-write to `.testing`** — test-coverage must write to both `.lang.python.tests.coverage` AND `.testing`

---

## Policy: `python`

Directory: `lunar-lib/policies/python/`

### Checks

| Check | What it does | Input |
|-------|-------------|-------|
| `lockfile-exists` | Ensures a lockfile exists (`poetry.lock`, `Pipfile.lock`, or pinned `requirements.txt`) | — |
| `linter-configured` | Ensures a linter is configured (ruff, flake8, or pylint) | — |
| `min-python-version` | Ensures Python version meets minimum | `min_python_version` (default `"3.9"`) |
| `min-python-version-cicd` | Ensures Python version in CI meets minimum | `min_python_version_cicd` (default `"3.9"`) |

### Policy Implementation Notes

- All checks should first verify `.lang.python` exists, skip if not a Python project
- `lockfile-exists`: Check `.lang.python.native.poetry_lock.exists` OR `.lang.python.native.pipfile_lock.exists`. For `requirements.txt`-only projects, check if dependencies have pinned versions.
- `linter-configured`: Check `.lang.python.native.linter` is not null/empty
- `min-python-version`: Compare `.lang.python.version` against threshold
- `min-python-version-cicd`: Check `.lang.python.cicd.cmds[].version` against threshold

---

## Implementation Steps

1. Create worktree `lunar-lib-wt-python` on branch `brandon/python`
2. Read `lunar-lib/collectors/golang/` as the reference — follow the same conventions
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
# Collector (test on multiple components)
lunar collector dev python.project --component github.com/pantalasa-cronos/auth
lunar collector dev python.project --component github.com/pantalasa-cronos/backend
lunar collector dev python.project --component github.com/pantalasa-cronos/frontend
lunar collector dev python.dependencies --component github.com/pantalasa-cronos/auth

# Policy
lunar policy dev python.lockfile-exists --component github.com/pantalasa-cronos/auth
lunar policy dev python.linter-configured --component github.com/pantalasa-cronos/auth
lunar policy dev python.min-python-version --component github.com/pantalasa-cronos/auth
lunar policy dev python.lockfile-exists --component github.com/pantalasa-cronos/backend
```

### Expected Results (pantalasa-cronos)

| Component | project | dependencies | lockfile-exists | linter-configured | min-python-version |
|-----------|---------|-------------|----------------|-------------------|-------------------|
| auth (Python) | PASS (detects Python) | PASS (has requirements.txt) | Verify lockfile type | Verify linter config | PASS if >= 3.9 |
| twilio-python (Python) | PASS | PASS | Verify | Verify | Verify |
| backend (Go) | exits cleanly | exits cleanly | SKIP (not Python) | SKIP | SKIP |
| frontend (Node) | exits cleanly | exits cleanly | SKIP (not Python) | SKIP | SKIP |

*These are draft expected results — verify and adjust before handing off.*

### Edge Cases to Test

1. **Component with no Python files** — Collector exits cleanly, all policies skip
2. **Python project with no lockfile and unpinned `requirements.txt`** — `lockfile-exists` should FAIL
3. **Poetry project with `poetry.lock`** — `lockfile-exists` should PASS, build_systems should include `"poetry"`
4. **Project with `pyproject.toml` but no `[tool.ruff]` or `.ruff.toml`** — `linter-configured` should FAIL
