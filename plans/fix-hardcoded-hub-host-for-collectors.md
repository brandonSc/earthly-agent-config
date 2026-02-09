# Fix hardcoded `localhost` hub host for collector env injection

## Background

PR [#946](https://github.com/earthly/lunar/pull/946) ([ENG-393](https://linear.app/earthly-technologies/issue/ENG-393)) injects hub connection env vars (`LUNAR_HUB_HOST`, `LUNAR_HUB_TOKEN`, `LUNAR_HUB_GRPC_PORT`, `LUNAR_HUB_HTTP_PORT`, `LUNAR_HUB_INSECURE`) into the collector execution environment so collectors can make RPC calls back to the hub (e.g. `lunar sql connection-string`).

That PR is ready for review and works correctly for the CI agent and local dev paths. However, the **hub-side path** has a bug: the hub host, ports, and insecure flag are hardcoded in `cmd/lunar-hub/main.go` instead of coming from config.

## The Problem

In `cmd/lunar-hub/main.go` lines 199-212:

```go
collectorExecutor := collect.NewCollectorExecutor(
    notifyCollector,
    cfg.Secrets.Collector,
    cfg.SnippetLogPrefix,
    cfg.BinDir,
    cfg.LockDir,
    "localhost",        // ← hardcoded
    cfg.AuthToken,
    cfg.GRPCPort,       // ← internal port (8000), not necessarily what collectors need
    cfg.HTTPPort,       // ← internal port (8001), not necessarily what collectors need
    true,               // ← hardcoded insecure
    snippetStore,
    snippetLogManager,
)
```

These values get injected into collector env vars via `HubConnEnv()`. When a collector runs `lunar sql connection-string`, the `lunar` CLI tries to gRPC-connect to `LUNAR_HUB_HOST:LUNAR_HUB_GRPC_PORT` — which resolves to `localhost:8000` inside the collector's Docker container. Since `localhost` in a container is the container itself (not the hub), the RPC call fails.

## How it should work

In demo deployments, everything runs in Docker compose. The hub is a service named `hub`. Other containers (like the CI agent) already reach it correctly:

```yaml
# From deploy/demo/ansible/roles/lunar/templates/compose.yml.j2
LUNAR_HUB_HOST: hub
LUNAR_HUB_GRPC_PORT: 8000
LUNAR_HUB_HTTP_PORT: 8001
LUNAR_HUB_INSECURE: "true"
```

Collectors also run as Docker containers in the same compose network, so `hub:8000` would resolve correctly. The `postgres:5432` address returned by `lunar sql connection-string` is also a Docker service name in the same network, so the full chain works — as long as the collector can reach the hub to make the RPC call.

## Proposed Fix

Add config fields to the hub config (`hub/config/config.go`) for the address that collectors should use to reach the hub. Something like:

```go
// In hub/config/config.go BaseConfig struct
CollectorHubHost     string `envconfig:"HUB_COLLECTOR_HUB_HOST" default:"localhost"`
CollectorHubGRPCPort int    `envconfig:"HUB_COLLECTOR_HUB_GRPC_PORT"`
CollectorHubHTTPPort int    `envconfig:"HUB_COLLECTOR_HUB_HTTP_PORT"`
CollectorHubInsecure bool   `envconfig:"HUB_COLLECTOR_HUB_INSECURE" default:"true"`
```

Then in `cmd/lunar-hub/main.go`, use these config values instead of hardcoded ones. If the collector-specific ports aren't set, fall back to the hub's own `GRPCPort`/`HTTPPort`.

Update the compose template (`deploy/demo/ansible/roles/lunar/templates/compose.yml.j2`) to set:

```yaml
HUB_COLLECTOR_HUB_HOST: hub
```

The naming convention is flexible — could also be `HUB_SNIPPET_HOST` or similar. The key point is: these values should come from config, not be hardcoded.

## Files to Change

1. **`hub/config/config.go`** — Add new config fields to `BaseConfig`
2. **`cmd/lunar-hub/main.go`** — Replace hardcoded values with config fields
3. **`deploy/demo/ansible/roles/lunar/templates/compose.yml.j2`** — Add the new env var(s)
4. **`deploy/demo/ansible/roles/lunar/templates/lunar.env.j2`** — Add the new env var(s) if needed

## QA Verification

A test collector (`sql-test`) is already set up in `pantalasa-cronos/lunar/collectors/sql-test/` and wired into `lunar-config.yml`. After deploying to cronos, verify with:

```bash
cd ~/code/earthly/pantalasa-cronos/lunar
export LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643
lunar component get-json github.com/pantalasa-cronos/backend | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('test', 'NOT FOUND'), indent=2))"
```

Expected result after fix:

```json
{
  "hub_env": {
    "grpc_port_set": true,
    "host_set": true,
    "http_port_set": true,
    "token_set": true
  },
  "sql_connection": {
    "exit_code": 0,
    "format_valid": true,
    "success": true
  }
}
```

## Related

- Depends on PR #946 being merged first (or can be stacked on top of branch `brandon/collector-hub-env`)
- Linear ticket: [ENG-393](https://linear.app/earthly-technologies/issue/ENG-393) (or create a new one for this follow-up)
