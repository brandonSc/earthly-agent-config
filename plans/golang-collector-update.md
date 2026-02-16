# Go Collector Update Plan

## Overview

Update the existing Go collector (`lunar-lib/collectors/golang/`) to align with the current CI collector best practices documented in LUNAR-PLUGIN-GUIDE.md. The CI sub-collectors currently use `jq` while running `native` on users' CI runners, which contradicts the guide.

This is a small, focused update — no new sub-collectors, just rewriting 3 existing CI scripts.

---

## What Needs to Change

### 1. `cicd.sh` — Remove `jq`, use `lunar collect`

**Before (uses `jq`):**
```bash
cmd_str=$(echo "$LUNAR_CI_COMMAND" | jq -r 'join(" ")')
version=$(go version | awk '{print $3}' | sed 's/go//' || echo "")
if [[ -n "$version" ]]; then
  jq -n --arg cmd "$cmd_str" --arg version "$version" \
    '{cmds: [{cmd: $cmd, version: $version}], source: {tool: "go", integration: "ci"}}' | \
    lunar collect -j ".lang.go.cicd" -
fi
```

**After (native-bash):**
```bash
version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo "")
if [[ -n "$version" ]]; then
  lunar collect ".lang.go.cicd.source.tool" "go" \
               ".lang.go.cicd.source.integration" "ci"
  # LUNAR_CI_COMMAND is available as a string in the environment for native collectors
  # Collect version — the command itself is already tracked by Lunar's CI instrumentation
  lunar collect ".lang.go.cicd.version" "$version"
fi
```

**Note:** Check how `LUNAR_CI_COMMAND` is provided in native mode. In container mode it's a JSON array, but native collectors may receive it differently. Test this and adjust accordingly.

### 2. `test-scope.sh` — Remove `jq`, use `lunar collect`

**Before (uses `jq`):**
```bash
if echo "$LUNAR_CI_COMMAND" | jq -e --arg val "$argument" 'index($val) != null' >/dev/null 2>&1; then
    scope="recursive"
# ...
jq -n --arg scope "$scope" '{scope: $scope, source: {...}}' | lunar collect -j .lang.go.tests -
jq -n '{source: {...}}' | lunar collect -j .testing -
```

**After (native-bash):**
```bash
# Check if ./... appears in the command (native string matching)
if echo "$LUNAR_CI_COMMAND" | grep -q '\./\.\.\.'; then
    scope="recursive"
else
    scope="package"
fi

lunar collect ".lang.go.tests.scope" "$scope" \
             ".lang.go.tests.source.tool" "go" \
             ".lang.go.tests.source.integration" "ci"

lunar collect ".testing.source.tool" "go test" \
             ".testing.source.integration" "ci"
```

### 3. `test-coverage.sh` — Partial update

This one is trickier because it uses `jq` for:
- Parsing `LUNAR_CI_COMMAND` JSON array to extract the `-coverprofile` flag value
- Building the output JSON with `--rawfile` for the coverage profile

The `go tool cover` dependency is fine (Go is installed since they're running `go test`). But the `jq` usage for command parsing and JSON construction should be replaced.

**Key changes:**
- Replace `jq -r 'index("-coverprofile")'` with native bash array parsing or grep
- Replace the `jq -n` output construction with individual `lunar collect` calls
- The raw profile content (`--rawfile`) can be piped: `cat "$coverprofile_path" | lunar collect -j ".lang.go.tests.coverage.native.profile" -`

**After (native-bash):**
```bash
# Extract -coverprofile path from command args using native bash
coverprofile_path=""
prev=""
for arg in $LUNAR_CI_COMMAND; do
  if [[ "$prev" == "-coverprofile" ]]; then
    coverprofile_path="$arg"
    break
  fi
  # Also handle -coverprofile=path format
  if [[ "$arg" == -coverprofile=* ]]; then
    coverprofile_path="${arg#-coverprofile=}"
    break
  fi
  prev="$arg"
done

if [[ -z "$coverprofile_path" || ! -f "$coverprofile_path" ]]; then
  exit 0
fi

coverage_pct=$(go tool cover -func="$coverprofile_path" 2>/dev/null | awk '/^total:/ {print $NF}' | sed 's/%$//' || echo "")

if [[ -n "$coverage_pct" ]]; then
  lunar collect -j ".lang.go.tests.coverage.percentage" "$coverage_pct" \
               ".lang.go.tests.coverage.profile_path" "$coverprofile_path" \
               ".lang.go.tests.coverage.source.tool" "go cover" \
               ".lang.go.tests.coverage.source.integration" "ci"
fi
```

---

## Implementation Steps

1. Create worktree `lunar-lib-wt-golang-update` on branch `brandon/golang-native-ci`
2. Rewrite `cicd.sh` without `jq`
3. Rewrite `test-scope.sh` without `jq`
4. Rewrite `test-coverage.sh` without `jq`
5. Test all 3 CI sub-collectors using `lunar collector dev` on pantalasa-cronos Go components
6. Verify code sub-collectors (`project`, `dependencies`, `golangci-lint`) still work unchanged
7. Complete pre-push checklist
8. Create draft PR

---

## Testing

```bash
# CI sub-collectors (the ones being changed)
lunar collector dev golang.cicd --component github.com/pantalasa-cronos/backend
lunar collector dev golang.test-scope --component github.com/pantalasa-cronos/backend
lunar collector dev golang.test-coverage --component github.com/pantalasa-cronos/backend

# Code sub-collectors (unchanged, regression test)
lunar collector dev golang.project --component github.com/pantalasa-cronos/backend
lunar collector dev golang.dependencies --component github.com/pantalasa-cronos/backend
lunar collector dev golang.golangci-lint --component github.com/pantalasa-cronos/backend

# Non-Go component (should exit cleanly)
lunar collector dev golang.project --component github.com/pantalasa-cronos/frontend
```

### Expected Results

| Sub-collector | backend (Go) | frontend (Node) |
|---------------|-------------|----------------|
| cicd | Records Go version | N/A (CI hook, only fires on `go` commands) |
| test-scope | Records scope | N/A |
| test-coverage | Records percentage | N/A |
| project | PASS (unchanged) | exits cleanly |
| dependencies | PASS (unchanged) | exits cleanly |
| golangci-lint | PASS (unchanged) | exits cleanly |

*Verify CI sub-collector output matches the current output format — this is a refactor, not a behavior change.*

### Edge Cases

1. **`LUNAR_CI_COMMAND` format in native mode** — Verify how the command is provided. In container mode it's a JSON array; in native mode it may be a plain string. The rewrite must handle whichever format is used.
2. **`-coverprofile=path` vs `-coverprofile path`** — Both formats should be handled in the native bash parsing.
3. **No `go` in PATH** — CI sub-collectors should gracefully handle this (exit 0, not error).
