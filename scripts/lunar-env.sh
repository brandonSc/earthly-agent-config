#!/usr/bin/env bash
# lunar-env — switch between Lunar deployment environments.
#
# Designed to be SOURCED into your shell (so env-var exports actually
# stick to the parent shell). Add to ~/.zshrc or ~/.bashrc:
#
#     source ~/code/earthly/earthly-agent-config/scripts/lunar-env.sh
#
# Then:
#
#     lunar-env earthly-internal
#     lunar-env cronos
#     lunar-env pantalasa
#     lunar-env             # show current + list available
#
# What it does, per env:
#   - sets AWS_PROFILE to the right profile (assumes-role, may prompt MFA)
#   - switches kubectl context (running `aws eks update-kubeconfig` lazily)
#   - exports LUNAR_HUB_URL + LUNAR_HUB_TOKEN (fetched from the cluster)
#   - sets LUNAR_NAMESPACE for kubectl shortcuts
#   - prints a one-screen summary so you know where you landed
#
# What it does NOT do:
#   - refresh AWS MFA automatically. If it's stale you'll get a clear
#     error pointing at the right command. Run that command yourself
#     (because the MFA prompt only works in a TTY shell).
#
# Source: https://github.com/brandonSc/earthly-agent-config/blob/main/scripts/lunar-env.sh

# ----------------------------------------------------------------------------
# Environment registry (single source of truth)
# ----------------------------------------------------------------------------
# Each env is defined as a function returning newline-separated KEY=VALUE
# lines. Editing this block is how you add a new environment.

_lunar_env_earthly-internal() {
    cat <<'EOF'
name=earthly-internal
description=Internal dogfood cluster on AWS EKS, tenant earthly-internal
aws_profile=lunar-install
aws_account=527371380956
aws_region=us-west-2
eks_cluster=lunar-earthly-internal
hub_url=https://internal.demo.earthly.dev
grafana_url=https://internal.demo.earthly.dev
namespace=lunar
snippet_namespace=lunar-snippets
chart_version=0.8.2
notes=Run by Brandon. See LUNAR-EARTHLY-INTERNAL-OPS.md for recovery procedures.
EOF
}

_lunar_env_cronos() {
    cat <<'EOF'
name=cronos
description=Pantalasa-cronos demo tenant on the lunar-demo EKS cluster
aws_profile=demo
aws_account=455314823777
aws_region=us-west-2
eks_cluster=lunar-demo
hub_url=https://cronos.demo.earthly.dev
grafana_url=https://cronos.demo.earthly.dev
namespace=lunar
snippet_namespace=lunar
chart_version=0.8.0
notes=Shares the lunar-demo EKS cluster with pantalasa. Image tag 9cc00b55 (older than internal). 5 nodes, operator_max_concurrent=20.
EOF
}

_lunar_env_pantalasa() {
    cat <<'EOF'
name=pantalasa
description=Legacy lunar.demo.earthly.dev tenant (EC2/Compose -> EKS bake)
aws_profile=demo
aws_account=455314823777
aws_region=us-west-2
eks_cluster=lunar-demo
hub_url=https://lunar.demo.earthly.dev
grafana_url=https://lunar.demo.earthly.dev
namespace=lunar-pantalasa
snippet_namespace=lunar-pantalasa
chart_version=0.6.1
notes=Older chart (0.6.1) image tag 0b3eed92. May still be partly on the legacy EC2 stack — confirm before assuming EKS-side state.
EOF
}

# List of all known envs.
_lunar_env_list() {
    cat <<'EOF'
earthly-internal
cronos
pantalasa
EOF
}

# ----------------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------------

lunar-env() {
    local env="$1"

    if [ -z "$env" ]; then
        _lunar_env_show_current
        echo
        _lunar_env_show_available
        return 0
    fi

    if [ "$env" = "-h" ] || [ "$env" = "--help" ]; then
        _lunar_env_help
        return 0
    fi

    if ! _lunar_env_list | grep -qFx "$env"; then
        echo "lunar-env: unknown environment '$env'" >&2
        echo >&2
        _lunar_env_show_available >&2
        return 1
    fi

    local cfg
    cfg="$("_lunar_env_${env}")"

    local aws_profile aws_account aws_region eks_cluster hub_url namespace snippet_namespace grafana_url chart_version notes description
    aws_profile=$(echo "$cfg" | grep '^aws_profile=' | cut -d= -f2-)
    aws_account=$(echo "$cfg" | grep '^aws_account=' | cut -d= -f2-)
    aws_region=$(echo "$cfg" | grep '^aws_region=' | cut -d= -f2-)
    eks_cluster=$(echo "$cfg" | grep '^eks_cluster=' | cut -d= -f2-)
    hub_url=$(echo "$cfg" | grep '^hub_url=' | cut -d= -f2-)
    grafana_url=$(echo "$cfg" | grep '^grafana_url=' | cut -d= -f2-)
    namespace=$(echo "$cfg" | grep '^namespace=' | cut -d= -f2-)
    snippet_namespace=$(echo "$cfg" | grep '^snippet_namespace=' | cut -d= -f2-)
    chart_version=$(echo "$cfg" | grep '^chart_version=' | cut -d= -f2-)
    notes=$(echo "$cfg" | grep '^notes=' | cut -d= -f2-)
    description=$(echo "$cfg" | grep '^description=' | cut -d= -f2-)

    echo "[lunar-env] switching to: $env"
    echo "  ($description)"
    echo

    # ---- 1. AWS profile + MFA check
    export AWS_PROFILE="$aws_profile"
    echo "  AWS profile: $aws_profile (account $aws_account, $aws_region)"

    if ! aws --no-cli-auto-prompt sts get-caller-identity --query 'Account' --output text >/dev/null 2>&1; then
        echo "  ✗ AWS creds stale or missing. Refresh with:"
        echo
        echo "      rm -f ~/.aws/cli/cache/*.json"
        echo "      AWS_PROFILE=$aws_profile aws eks list-clusters --region $aws_region"
        echo "      # (enter your MFA TOTP when prompted)"
        echo
        echo "    Then re-run: lunar-env $env"
        return 1
    fi
    echo "  ✓ AWS creds fresh"

    # ---- 2. kubectl context
    local kctx="arn:aws:eks:${aws_region}:${aws_account}:cluster/${eks_cluster}"
    if ! kubectl config get-contexts -o name 2>/dev/null | grep -qFx "$kctx"; then
        echo "  → kubectl context not configured; running aws eks update-kubeconfig"
        if ! aws --no-cli-auto-prompt eks update-kubeconfig --name "$eks_cluster" --region "$aws_region" >/dev/null 2>&1; then
            echo "  ✗ aws eks update-kubeconfig failed. Check that the EKS cluster name is correct."
            return 1
        fi
    fi
    kubectl config use-context "$kctx" >/dev/null 2>&1 || {
        echo "  ✗ kubectl config use-context failed for $kctx"
        return 1
    }
    echo "  ✓ kubectl context: $kctx"

    # ---- 3. Hub URL + token
    export LUNAR_HUB_URL="$hub_url"
    echo "  ✓ LUNAR_HUB_URL=$hub_url"

    local token
    token=$(kubectl -n "$namespace" get secret lunar-auth-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null)
    if [ -n "$token" ]; then
        export LUNAR_HUB_TOKEN="$token"
        echo "  ✓ LUNAR_HUB_TOKEN set (${#token} chars)"
    else
        unset LUNAR_HUB_TOKEN
        echo "  ! couldn't read lunar-auth-token from namespace '$namespace' — LUNAR_HUB_TOKEN unset"
    fi

    # ---- 4. Convenience env vars
    export LUNAR_NAMESPACE="$namespace"
    export LUNAR_SNIPPET_NAMESPACE="$snippet_namespace"
    export LUNAR_ENV="$env"
    echo "  ✓ LUNAR_NAMESPACE=$namespace  LUNAR_SNIPPET_NAMESPACE=$snippet_namespace"
    echo "  ✓ Grafana: $grafana_url  (chart $chart_version)"

    if [ -n "$notes" ]; then
        echo
        echo "  Notes: $notes"
    fi

    return 0
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

_lunar_env_show_current() {
    echo "Current Lunar env: ${LUNAR_ENV:-<none set>}"
    [ -n "$AWS_PROFILE" ]      && echo "  AWS_PROFILE=$AWS_PROFILE"
    [ -n "$LUNAR_HUB_URL" ]    && echo "  LUNAR_HUB_URL=$LUNAR_HUB_URL"
    [ -n "$LUNAR_NAMESPACE" ]  && echo "  LUNAR_NAMESPACE=$LUNAR_NAMESPACE"
    local kctx
    kctx=$(kubectl config current-context 2>/dev/null) && echo "  kubectl ctx: $kctx"
}

_lunar_env_show_available() {
    echo "Available environments:"
    while IFS= read -r env; do
        local cfg desc
        cfg="$("_lunar_env_${env}")"
        desc=$(echo "$cfg" | grep '^description=' | cut -d= -f2-)
        printf "  %-20s %s\n" "$env" "$desc"
    done < <(_lunar_env_list)
    echo
    echo "Usage: lunar-env <name>"
}

_lunar_env_help() {
    cat <<'EOF'
lunar-env — switch between Lunar deployment environments.

Usage:
  lunar-env                   show current env + list available
  lunar-env <name>            switch to env
  lunar-env -h | --help       this help

Adds to your shell:
  AWS_PROFILE                  the right AWS profile for the env
  LUNAR_HUB_URL                Hub gRPC URL (also used by Grafana)
  LUNAR_HUB_TOKEN              Hub API token (read from cluster secret)
  LUNAR_NAMESPACE              the chart's release namespace
  LUNAR_SNIPPET_NAMESPACE      where ephemeral snippet pods run
  LUNAR_ENV                    name of the current env

Also runs `kubectl config use-context` for the env's EKS cluster.

If AWS creds are stale, lunar-env will tell you exactly which command to
run to refresh MFA — it can't prompt for MFA itself from inside a
non-interactive helper.
EOF
}

# ----------------------------------------------------------------------------
# Allow this file to be RUN directly (not just sourced) — useful for `bash
# -c 'source … && lunar-env earthly-internal'` style invocations.
# When sourced, this block is a no-op because $0 is the parent shell.
# ----------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    if [ $# -eq 0 ]; then
        echo "Source this file from your shell to get the lunar-env command:"
        echo "  source $0"
        echo
        echo "Or run as: $0 <env-name>  (only shows info; can't export to your parent shell)"
        exit 1
    fi
    lunar-env "$@"
fi
