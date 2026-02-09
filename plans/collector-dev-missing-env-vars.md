# ENG-336: Env vars not set in collector dev mode

Linear ticket: [ENG-336](https://linear.app/earthly-technologies/issue/ENG-336/lunar-component-id-and-other-env-vars-not-set-in-collector-dev-mode)

## Problem

Several documented collector env vars are never set — not just in `collector dev` mode, but across **all execution paths** (CI agent, hub-side, dev). The env vars exist in the docs (`docs/bash-sdk/collector.md`) but have no corresponding `SnippetEnv` constants and no code that sets them.

### Missing env vars (no implementation anywhere)

| Env Var | Description | Source |
|---------|-------------|--------|
| `LUNAR_COLLECTOR_NAME` | The name of the collector | `snippet.Name` |
| `LUNAR_COLLECTOR_CI_PIPELINE` | The CI pipeline of the component | manifest component config |
| `LUNAR_COMPONENT_DOMAIN` | The domain of the component | manifest component |
| `LUNAR_COMPONENT_OWNER` | The owner of the component | manifest component |
| `LUNAR_COMPONENT_TAGS` | The tags of the component | manifest component (JSON array) |
| `LUNAR_COMPONENT_META` | The metadata of the component | manifest component (JSON object) |

### Env vars that DO work

| Env Var | Set via |
|---------|---------|
| `LUNAR_COMPONENT_ID` | `CIEnv.ToLunarEnv()` ✅ |
| `LUNAR_COMPONENT_GIT_SHA` | `CIEnv.ToLunarEnv()` ✅ |
| `LUNAR_COMPONENT_HEAD_BRANCH` | `CIEnv.ToLunarEnv()` ✅ |
| `LUNAR_COMPONENT_BASE_BRANCH` | `CIEnv.ToLunarEnv()` ✅ |
| `LUNAR_COMPONENT_PR` | `CIEnv.ToLunarEnv()` ✅ |
| `LUNAR_BIN_DIR` | `engine/helpers.go executionEnv()` ✅ |
| `LUNAR_HUB_*` | PR #946 ✅ |
| `LUNAR_SECRET_*` | `SnippetContext.Secrets` ✅ |
| `LUNAR_CI_*` | `CIEnv.ToLunarEnv()` ✅ (CI collectors only) |

## Root Cause

The `SnippetEnv` constants in `snippets/executor.go` only cover CI-related and hub-connection env vars. Component-level metadata (domain, owner, tags, meta) and collector identity (name, pipeline) were documented but never wired into the execution environment.

The `CIEnv` struct in `ci/ci.go` is focused on CI execution context (branches, SHAs, pipeline/job/step info), not component metadata from the manifest. No code path enriches the snippet context with component-level data from the manifest.

## Proposed Fix

### 1. Add `SnippetEnv` constants (`snippets/executor.go`)

```go
SnippetEnvCollectorName       SnippetEnv = "LUNAR_COLLECTOR_NAME"
SnippetEnvCollectorCIPipeline SnippetEnv = "LUNAR_COLLECTOR_CI_PIPELINE"
SnippetEnvComponentDomain     SnippetEnv = "LUNAR_COMPONENT_DOMAIN"
SnippetEnvComponentOwner      SnippetEnv = "LUNAR_COMPONENT_OWNER"
SnippetEnvComponentTags       SnippetEnv = "LUNAR_COMPONENT_TAGS"
SnippetEnvComponentMeta       SnippetEnv = "LUNAR_COMPONENT_META"
```

### 2. Fix `collector dev` path (`cmd/lunar/main.go`)

In `runCollectorDevCmd`, the manifest is already loaded (as `localManifest`). After building `snipCtx`, inject the missing vars:

- `LUNAR_COLLECTOR_NAME` from `snippet.Name`
- For `LUNAR_COMPONENT_DOMAIN`, `LUNAR_COMPONENT_OWNER`, `LUNAR_COMPONENT_TAGS`, `LUNAR_COMPONENT_META`: look up the component in the manifest by `componentName` and read its properties.

The component data is available in the manifest — check `localManifest.Components` or however components are stored in the `fetch.LocalManifest` struct.

### 3. Fix hub-side path (`hub/collect/executor.go`)

In `Execute()`, the `component *store.Component` is already available. After setting `SnippetEnvComponentID` and `SnippetEnvComponentGitSHA`, also set:

```go
snippetContext.ExtraEnv[snippets.SnippetEnvCollectorName] = collector.Name
snippetContext.ExtraEnv[snippets.SnippetEnvComponentDomain] = component.DomainID.String() // or however domain is stored
snippetContext.ExtraEnv[snippets.SnippetEnvComponentOwner] = component.Owner
// Tags and Meta need JSON serialization
```

### 4. Fix CI agent path (`ci/observe.go`)

In `runCollector()`, the matched components are available from `matchingComponents()`. Inject domain/owner/tags/meta from the component into `snippetContext.ExtraEnv`. Also set `LUNAR_COLLECTOR_NAME` from `snippet.Name`.

## Key files to modify

| File | Change |
|------|--------|
| `snippets/executor.go` | Add new `SnippetEnv` constants |
| `cmd/lunar/main.go` | Inject component metadata + collector name in `runCollectorDevCmd` |
| `hub/collect/executor.go` | Inject component metadata + collector name in `Execute()` |
| `ci/observe.go` | Inject component metadata + collector name in `runCollector()` |

## Important: check manifest/component data structures

Before implementing, read the data structures to understand how component properties (domain, owner, tags, meta) are stored:

- `snippets/fetch/` — `LocalManifest` struct and how components are represented
- `hub/store/` — `Component` struct (for hub-side path)
- `ci/observe.go` — `matchingComponents()` return type

Tags should be serialized as a JSON array string (e.g. `'["backend","go","SOC2"]'`).
Meta should be serialized as a JSON object string.

## Testing

Use the pantalasa-cronos test environment. Create a simple collector that echoes these env vars:

```bash
#!/bin/bash
lunar collect -j ".test.env.collector_name" "\"${LUNAR_COLLECTOR_NAME:-NOT_SET}\""
lunar collect -j ".test.env.component_domain" "\"${LUNAR_COMPONENT_DOMAIN:-NOT_SET}\""
lunar collect -j ".test.env.component_owner" "\"${LUNAR_COMPONENT_OWNER:-NOT_SET}\""
lunar collect -j ".test.env.component_tags" "\"${LUNAR_COMPONENT_TAGS:-NOT_SET}\""
```

Test with `lunar collector dev` locally first, then deploy and verify with `lunar component get-json`.
