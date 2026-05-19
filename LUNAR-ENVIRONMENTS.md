# Lunar Environments — Quick Switch Guide

We run three Lunar deployments. This doc is the single source of truth for the differences between them and how to switch between them.

## The envs

| | `earthly-internal` | `cronos` | `pantalasa` |
|---|---|---|---|
| **URL** | `https://internal.demo.earthly.dev` | `https://cronos.demo.earthly.dev` | `https://lunar.demo.earthly.dev` |
| **AWS account** | `527371380956` (sandbox) | `455314823777` (demo) | `455314823777` (demo) |
| **AWS profile** | `lunar-install` | `demo` | `demo` |
| **EKS cluster** | `lunar-earthly-internal` | `lunar-demo` | `lunar-demo` |
| **K8s namespace** | `lunar` | `lunar` | `lunar-pantalasa` |
| **Snippet namespace** | `lunar-snippets` | `lunar` | `lunar-pantalasa` |
| **Chart version** | `0.8.2` | `0.8.0` | `0.6.1` |
| **Hub image tag** | `2.0.0` (GHCR) | `9cc00b55` (docker.io) | `0b3eed92` (docker.io) |
| **Region** | `us-west-2` | `us-west-2` | `us-west-2` |
| **What it's for** | Internal dogfood — Earthly's own repos catalogued here | Pantalasa demo customer | Legacy lunar.demo bake — partly EKS, partly EC2 still |
| **Operator `maxConcurrent`** | 30 | 20 | (legacy chart) |
| **Run by** | Brandon | Brandon | Brandon (during bake) |

Cronos and Pantalasa share the same EKS cluster (`lunar-demo`) — they're separate K8s namespaces, separate helm releases, separate hostnames. EarthlyInternal is on its own cluster in a separate AWS account.

## Quick-switch script

```bash
# One-time: add to ~/.zshrc (or ~/.bashrc)
source ~/code/earthly/earthly-agent-config/scripts/lunar-env.sh

# Use:
lunar-env                   # show current + list available
lunar-env earthly-internal  # switch
lunar-env cronos
lunar-env pantalasa
```

After switching, these are set in your shell for the chosen env:

| Variable | Set to |
|---|---|
| `AWS_PROFILE` | The right profile (`lunar-install` or `demo`) |
| `LUNAR_HUB_URL` | Hub gRPC URL |
| `LUNAR_HUB_TOKEN` | Hub API token (auto-fetched from cluster) |
| `LUNAR_NAMESPACE` | The chart's namespace |
| `LUNAR_SNIPPET_NAMESPACE` | Where ephemeral snippet pods run |
| `LUNAR_ENV` | Name of the current env (for prompt/awareness) |

Plus `kubectl` context is set to the right EKS cluster.

## First-time setup

### 1. AWS profiles

Make sure both AWS profiles exist in your `~/.aws/config`. If you're missing one, add:

```ini
[profile lunar-install]
region          = us-west-2
role_arn        = arn:aws:iam::527371380956:role/OrganizationAccountAccessRole
source_profile  = default
mfa_serial      = arn:aws:iam::404851345508:mfa/<your-user>@earthly.dev

[profile demo]
region          = us-west-2
role_arn        = arn:aws:iam::455314823777:role/OrganizationAccountAccessRole
source_profile  = default
mfa_serial      = arn:aws:iam::404851345508:mfa/<your-user>@earthly.dev
```

(Replace `<your-user>` with your Earthly username. The `default` profile is whatever long-lived creds you already have at the root of the org.)

### 2. Refresh MFA per profile

The first time you use each profile (and once every ~hour after), you need to refresh the assumed-role STS credentials with MFA. **Don't use `aws sts get-caller-identity`** — it returns cached identity even when stale and skips the prompt. Use a command that actually exercises the assumed role:

```bash
# For earthly-internal:
rm -f ~/.aws/cli/cache/*.json
AWS_PROFILE=lunar-install aws eks list-clusters --region us-west-2

# For cronos / pantalasa:
rm -f ~/.aws/cli/cache/*.json
AWS_PROFILE=demo aws eks list-clusters --region us-west-2
```

Each will prompt for your 6-digit TOTP. Once cached, the `lunar-env` script can use them silently.

### 3. Source the script

```bash
echo 'source ~/code/earthly/earthly-agent-config/scripts/lunar-env.sh' >> ~/.zshrc
source ~/.zshrc
```

### 4. Try it

```bash
lunar-env earthly-internal
kubectl get pods               # should show the lunar-earthly-internal cluster's lunar ns
lunar-env cronos
kubectl get pods               # should show cronos namespace pods (lunar-demo cluster)
```

## What to check on each env

A 30-second-per-env health check:

```bash
lunar-env <env>

# Main pods up?
kubectl -n $LUNAR_NAMESPACE get pods | grep -E 'hub|operator|grafana'

# Snippet pods (ephemeral) — should be a churning population, not 0 forever
kubectl -n $LUNAR_SNIPPET_NAMESPACE get pods --no-headers | awk '{print $3}' | sort | uniq -c

# Hub recent log volume — 0 lines in last 5 min means something is wrong
kubectl -n $LUNAR_NAMESPACE logs deploy/lunar-hub --since=5m 2>&1 | wc -l

# Helm release status
helm -n $LUNAR_NAMESPACE list
```

## Switching context-aware queries

The Grafana SQL API curl recipe (in `LUNAR-EARTHLY-INTERNAL-OPS.md`) works for any env — just swap the URL and admin credentials. Each Grafana has its own admin password in 1Password.

## Footguns

- **Profile-stale-cache MFA confusion**: switching from `lunar-install` to `demo` for the first time after a system reboot will prompt for MFA. If you ran `aws sts get-caller-identity` in between, it might appear that you're already authenticated — but you're not, and the next real call will fail. Always use `aws eks list-clusters` for the MFA-forcing call.
- **`kubectl config current-context`** stays "sticky" between shell sessions because kubeconfig is a file. If you closed your terminal mid-task on cronos, the next time you open a shell `kubectl` is still pointing at cronos. Run `lunar-env` to re-confirm where you are.
- **`pantalasa` namespace is `lunar-pantalasa`, not `lunar`** — cronos took the `lunar` namespace name on the `lunar-demo` cluster. Watch out when copy-pasting kubectl commands between envs.
- **Image registries differ**: earthly-internal pulls from GHCR (`ghcr.io/earthly/lunar-*:2.0.0`); cronos+pantalasa pull from Docker Hub (`earthly/lunar-*:<sha>`). When debugging image-pull issues, check which registry the env uses.

## Adding a new environment

Edit `scripts/lunar-env.sh` and add a new `_lunar_env_<name>()` function defining the env's fields, plus add the name to `_lunar_env_list()`. Update the table at the top of this doc. That's it.
