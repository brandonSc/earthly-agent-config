# `earthly-internal` Cluster Operations Cheat Sheet

Operating reference for the `earthly-internal` Lunar dogfood cluster on AWS EKS. Covers access, common commands, recovery procedures, and known footguns.

> Companion doc: `LUNAR-CUSTOMER-INSTALL-WALKTHROUGH.md` is the day-of guide for *installing* Lunar somewhere new. This doc is the day-to-day guide for *running* the one we already have.

Linear tickets referenced throughout: [ENG-705](https://linear.app/earthly-technologies/issue/ENG-705) (BestEffort QoS), [ENG-706](https://linear.app/earthly-technologies/issue/ENG-706) (elastic recursion), [ENG-707](https://linear.app/earthly-technologies/issue/ENG-707) (Hub+operator deadlock).

---

## Quick reference

| Thing | Value |
|---|---|
| Cluster | `lunar-earthly-internal` (EKS, `us-west-2`, AWS account `527371380956`) |
| kubectl context | `arn:aws:eks:us-west-2:527371380956:cluster/lunar-earthly-internal` |
| Hostname | `internal.demo.earthly.dev` (also `lunar-internal.demo.earthly.dev` legacy alias for webhooks) |
| AWS profile | `lunar-install` (assumes role; requires MFA) |
| Helm release | `lunar` in `lunar` namespace |
| Chart version | `0.8.2` (from `earthly/lunar` helm repo) |
| Image registry | `ghcr.io/earthly/*:2.0.0` (pulled with regcred from licence JWT) |
| Snippet namespace | `lunar-snippets` |
| Source-of-truth values | [`earthly/lunar-install/values.yaml`](https://github.com/earthly/lunar-install/blob/main/values.yaml) |

---

## 1Password items (Brandon to populate)

- **AWS MFA**: Brandon's TOTP for `arn:aws:iam::404851345508:mfa/brandon@earthly.dev`
- **Grafana admin password** (`internal.demo.earthly.dev`): `[1Password: lunar-earthly-internal grafana admin]`
- **Lunar Hub API token**: `[1Password: lunar-earthly-internal hub auth-token]`
- **GitHub App private key**: `[1Password: lunar-earthly-internal github-app private-key]`
- **GitHub App webhook secret**: `[1Password: lunar-earthly-internal github-webhook]`
- **Snippet secrets (`GH_TOKEN`)**: `[1Password: lunar-earthly-internal snippet-secrets]`
- **Hub licence JWT (with-telemetry)**: `[1Password: lunar-earthly-internal licence with-telemetry]`
- **Hub licence JWT (without-telemetry)**: `[1Password: lunar-earthly-internal licence without-telemetry]`
- **GHCR pull credential**: derived from licence JWT via `lunar licence pull-secret`; rotated by reissuing licence
- **Docker Hub creds (legacy regcred)**: `[1Password: brandonschurman/dockerhub]` — no longer used after GHCR migration but kept for emergency rollback

---

## Auth refresh (the AWS MFA dance)

The `lunar-install` profile assumes a cross-account role with MFA. Cached creds expire every ~1 hour. **Don't use `aws sts get-caller-identity`** to refresh — it returns cached identity and skips the MFA prompt. Instead:

```bash
# Nuke the stale cache + force a fresh role assumption with MFA
rm -f ~/.aws/cli/cache/*.json
aws eks list-clusters --region us-west-2
# → enter your 6-digit MFA code when prompted

# Verify (should not prompt)
kubectl get nodes
```

For cronos comparisons (different AWS account):
```bash
AWS_PROFILE=demo aws eks list-clusters --region us-west-2   # MFA prompt
aws eks update-kubeconfig --name lunar-demo --region us-west-2 --alias cronos --profile demo
kubectl --context=cronos get ns
```

---

## Cluster topology

- **4× m5.large nodes** (default; EKS managed node group)
- **Hub, operator, grafana** in `lunar` namespace (chart-managed)
- **Snippet pods** in `lunar-snippets` namespace (operator-managed, ephemeral)
- **ingress-nginx** in `ingress-nginx` namespace
- **cert-manager** in `cert-manager` namespace

Ingress hostname split (no Caddy here, NGINX with path-based routing):

| Path | Backend |
|---|---|
| `/hubapi\..*` | Hub gRPC (custom ingress in `lunar-install/k8s/lunar-hub-ingress.yaml`) |
| `/webhooks`, `/logs` | Hub HTTP |
| everything else (incl. `/`) | Grafana |

Legacy `lunar-internal.demo.earthly.dev` host kept alive for old webhooks (see `lunar-install/k8s/lunar-hub-old-alias.yaml`).

---

## Grafana access

UI: <https://internal.demo.earthly.dev/>

Credentials: see 1Password (note: the Grafana admin password was rotated via the UI at some point, so the K8s `lunar-grafana-admin` Secret may be stale — trust 1Password).

CLI access to Grafana's SQL API (very useful for cluster introspection without UI):

```bash
PASS=$(< /tmp/grafana-pass-internal.txt)  # paste from 1Password

curl -s -u "admin:$PASS" -X POST \
  "https://internal.demo.earthly.dev/api/ds/query" \
  -H "Content-Type: application/json" \
  -d '{"queries":[{"refId":"A",
        "datasource":{"uid":"PCC52D03280B7034C","type":"grafana-postgresql-datasource"},
        "rawSql":"SELECT 1",
        "format":"table"}],
       "from":"now-1h","to":"now"}'
```

Common queries (replace the `rawSql` body):

```sql
-- Snippet run rate by status, last 5 min
SELECT status, exit_code, count(*)
FROM hub.snippet_runs
WHERE started_at > NOW() - INTERVAL '5 minutes'
GROUP BY status, exit_code ORDER BY count DESC;

-- River queue state right now
SELECT queue, state, count(*) FROM queue.river_job
WHERE created_at > now() - interval '2 hours'
GROUP BY queue, state ORDER BY queue, state;

-- Stale "running" River jobs (zombies — see ENG-707)
SELECT queue, count(*), to_char(now()-min(attempted_at),'HH24:MI:SS') age
FROM queue.river_job WHERE state='running' GROUP BY queue;

-- All runs for one PR
SELECT s.name, r.status, r.exit_code,
       to_char(r.started_at,'HH24:MI:SS') started
FROM hub.snippet_runs r JOIN hub.snippets s ON s.id = r.snippet_id
WHERE r.dimensions->>'pr' = '<PR_NUMBER>'
ORDER BY r.started_at DESC LIMIT 50;
```

---

## Helm operations

```bash
cd ~/code/earthly/lunar-install

# Inspect current state
helm -n lunar list
helm -n lunar history lunar | tail -5
helm -n lunar get values lunar

# Upgrade (ALWAYS pin --version explicitly)
helm upgrade lunar earthly/lunar --version 0.8.2 -n lunar -f values.yaml

# Rollback to a prior revision
helm -n lunar rollback lunar <rev>
```

**Don't ever run `helm upgrade --force`** — it tries to recreate PVCs (kills Grafana storage). Hit this once already.

**Don't run `helm upgrade` without `--version`** — pulls the latest chart from the helm repo which may have unexpected requirements (chart 0.7 → 0.8 introduced the licence-required secret, which broke us once).

---

## Hub/operator/snippet runtime tuning

Live knobs (in `values.yaml`):

- `operator.maxConcurrent: 30` — bumped from default 10 because measured throughput uplift (~6 → ~18 concurrent pods, ~23 → ~29 collect_run/min). Worth the slight oversubscription risk on 4× m5.large.
- `operator.snippetContainerSpecCollector.resources.limits.memory: 2Gi` — right-sized for `golang.golangci-lint` (peaks ~1.6Gi); originally 4Gi caused the 2026-05-16 OOM cascade.
- `operator.snippetContainerSpecCollector.resources.requests.memory: 512Mi`
- `hub.licence.secretName: lunar-hub-licence` — switch between with/without-telemetry by reapplying the secret (see "Licence types" below).

Hardcoded (Go source, requires Hub rebuild + new image tag):

- `hub/queue/workers/collect/register.go:44` → `MaxWorkers: 10` (see ENG-707). At small scale this isn't the bottleneck; for large customers it eventually will be.

---

## Licence types (with-telemetry vs without-telemetry)

The licence JWT carries Elasticsearch credentials that Hub propagates to all snippet containers via env vars `LUNAR_ELASTIC_URL` + `LUNAR_ELASTIC_API_KEY`.

- **with-telemetry**: snippet init/sidecar containers connect to Earthly's Elasticsearch endpoint. **Currently triggers ENG-706** — if Elasticsearch returns `errors: true` (field mapping conflict), the init container hangs forever on its logger Shutdown, snippet pod stays Init:0/1 indefinitely, pile-up causes OOM cascade.
- **without-telemetry**: no elastic env vars propagated. Snippet pods exit cleanly. Safe in production.

**For now (until ENG-706 lands): always run without-telemetry on this cluster.**

Swap licences:

```bash
kubectl -n lunar create secret generic lunar-hub-licence \
  --from-file=hub-licence.jwt=<path/to>.jwt \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lunar rollout restart deploy/lunar-hub
```

Hub log line confirms which licence is loaded:
```
"msg":"validated hub licence" ... "elastic":{"url":"...","api_key":"[REDACTED]"}}
```
If `elastic` block is absent or empty, we're on without-telemetry.

---

## Recovery procedures

### 1. Pipeline deadlocked — 0 snippet pods, "failed to fetch pod status" spam (ENG-707)

Symptoms: queued work piling up, no pods scheduling, operator log spamming `failed to fetch pod status for progress`, River queue shows N "running" jobs for 30min+ with no actual pods.

Fix (order matters):
```bash
kubectl -n lunar rollout restart deploy/lunar-hub        # releases River job claims
kubectl -n lunar rollout status deploy/lunar-hub --timeout=90s
kubectl -n lunar rollout restart deploy/lunar-operator   # clears phantom pod tracking
kubectl -n lunar rollout status deploy/lunar-operator --timeout=90s
# may need to force-delete the most-recent operator pod if it CrashLoopBackOffs trying to reach Hub:
kubectl -n lunar delete pod -l app.kubernetes.io/component=operator --grace-period=0 --force
```

### 2. Node OOM cascade — all kubelets stop heartbeating

Symptoms: `kubectl get nodes` shows `NotReady`, EC2 instances are `running` per AWS, kubelet:10250 unreachable, snippet pods piled up.

Fix:
```bash
# Identify the EC2 instances
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=tag:eks:cluster-name,Values=lunar-earthly-internal" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,LaunchTime]' \
  --output table

# Terminate (ASG auto-replaces)
aws ec2 terminate-instances --region us-west-2 --instance-ids <i-...> <i-...> ...
# Wait ~5-10 min for replacements to register Ready
```

The root cause was over-aggressive collector resource limits (since fixed in `values.yaml`). If it happens again, double-check that the values are still right-sized and consider why the math broke.

### 3. Grafana UI returns 503 / connection refused

Almost always `ingress-nginx-controller` got evicted under memory pressure (it's Burstable QoS with no limits — see ENG-705). Bounce it:

```bash
kubectl -n ingress-nginx rollout restart deploy/ingress-nginx-controller
```

### 4. Image pull failures on snippet pods (`401 Unauthorized` from GHCR)

The `lunar-snippet-pod` ServiceAccount in `lunar-snippets` needs `regcred` attached, and `regcred` needs to exist in *both* `lunar` and `lunar-snippets` namespaces. The chart only auto-attaches it in `lunar`.

Fix:
```bash
# Copy regcred to lunar-snippets if missing
kubectl -n lunar get secret regcred -o yaml \
  | sed '/namespace:/d;/resourceVersion:/d;/uid:/d;/creationTimestamp:/d' \
  | kubectl -n lunar-snippets apply -f -

# Attach to SA
kubectl -n lunar-snippets patch serviceaccount lunar-snippet-pod \
  -p '{"imagePullSecrets":[{"name":"regcred"}]}'
```

### 5. Stuck collector batch (one specific snippet hung)

If a particular collector type hangs (e.g., `golang.golangci-lint` from earlier OOM era):

```bash
# Find stuck pods
kubectl -n lunar-snippets get pods --no-headers | awk '$3~/Init|Pending/ {print $1}'

# Force-delete (operator will recreate from the River queue if MaxAttempts allows)
... | xargs -P10 -I{} kubectl -n lunar-snippets delete pod {} --grace-period=0 --force

# Bounce operator to flush in-memory tracking
kubectl -n lunar rollout restart deploy/lunar-operator
```

---

## Triggering work for testing

```bash
export LUNAR_HUB_URL=https://internal.demo.earthly.dev
export LUNAR_HUB_TOKEN=$(kubectl -n lunar get secret lunar-auth-token -o jsonpath='{.data.token}' | base64 -d)

# Re-run code collectors for recent PRs
lunar hub run-code-collectors --include-pr-commits --pr-max-age-days 1

# Push an empty commit to a PR to trigger fresh collector runs
# (only safe on PRs we own — never push to teammate branches)
git commit --allow-empty -m "test: retrigger collectors" && git push
```

The lunar CLI is built from source:
```bash
cd ~/code/earthly/lunar
git pull origin main
[ "$(git rev-parse HEAD)" != "$LOCAL_SHA" ] && earthly +build-cli && sudo cp dist/lunar-linux-amd64 /usr/local/bin/lunar
```

---

## Known footguns

- **`helm upgrade --force`** — recreates PVCs. Never run this. Use the `kubectl set env` workaround for one-off env changes if needed.
- **`aws sts get-caller-identity`** — does NOT trigger MFA refresh even when cache is stale. Use a command that hits an assumed-role API like `aws eks list-clusters`.
- **Operator pod is BestEffort QoS** (ENG-705) — kernel kills it first under memory pressure. Compounds the OOM cascade.
- **Hub propagates licence env vars to snippet pods** — applying a with-telemetry licence will hang every new snippet pod (ENG-706). Don't swap to with-telemetry until ENG-706 lands.
- **Hub `MaxWorkers: 10` is hardcoded** (ENG-707) — eventual scaling cap but not the binding limit at current load.
- **chart's `OPERATOR_HUB_HOST` was hardcoded** until [earthly/charts PR #34](https://github.com/earthly/charts/pull/34) — if you ever see a duplicate-env warning on `lunar-operator`, that's the old workaround creeping back; clean live state before any helm upgrade.
- **Snippet pods don't auto-attach regcred** — chart bug, see Recovery #4. If snippet pulls fail with 401, that's the first thing to check.

---

## Useful one-liners

```bash
# Cluster overview
kubectl get nodes && kubectl -n lunar get pods && kubectl -n lunar-snippets get pods --no-headers | awk '{print $3}' | sort | uniq -c

# Hub last 5 log lines (parsed)
kubectl -n lunar logs deploy/lunar-hub --tail=5 | python3 -c "import sys,json; [print(f'{r[\"time\"][11:19]} {r[\"level\"]:>5} {r[\"msg\"]}') for r in (json.loads(l) for l in sys.stdin if l.strip())]"

# Operator's "what is it doing" snapshot (msg counts last 1 min)
kubectl -n lunar logs deploy/lunar-operator --since=1m | python3 -c "import sys,json; from collections import Counter; c=Counter(json.loads(l)['msg'] for l in sys.stdin if l.strip()); [print(f'  {v:>3}× {k}') for k,v in c.most_common(10)]"

# Quick health: pod counts + Hub heartbeat
kubectl -n lunar get pods --no-headers; echo "---"; kubectl -n lunar logs deploy/lunar-hub --tail=1 | python3 -c "import sys,json; r=json.load(sys.stdin); print(f'Hub last log: {r[\"time\"]}')"
```

---

*Originally drafted from the 2026-05-15 → 2026-05-17 dogfood incident sessions. Update freely as we learn more.*
