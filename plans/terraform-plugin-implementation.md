# Terraform Collector & IaC/Terraform Policies — Implementation Plan

Import the Terraform collector and corresponding policies from `meridian/lunar/` into `lunar-lib` as first-class plugins.

---

## Context

The meridian demo environment has a working Terraform collector and policy at:
- `meridian/lunar/collectors/terraform/` — parses `.tf` files with `hcl2json`, detects internet accessibility, WAF protection, and datastore deletion protection
- `meridian/lunar/policies/terraform/` — three checks: `terraform-valid`, `terraform-has-waf`, `terraform-has-delete-protection`

These currently write to `.terraform.*` paths. The canonical Component JSON schema defines `.iac.*` for Infrastructure as Code data (see `ai-context/component-json/cat-iac.md` and the IaC example in `conventions.md:330-357`).

### Design Principle: Thin Collector, Smart Policies

The meridian collector does significant analysis in bash (WAF detection, datastore checking, internet accessibility). **This should move to the policies in Python.** The collector's job is simple:

1. Find `.tf` files
2. Parse each with `hcl2json`
3. Write file validity to `.iac.files[]`
4. Write full parsed HCL JSON to `.iac.native.terraform.files[]`
5. Write source metadata

All analysis (WAF, datastores, providers, modules, backend) happens in policy Python code where it's easier to maintain and test.

### Two Policies, Not One

- **`policies/iac`** — Generic IaC guardrails: validity, WAF protection, datastore protection. Concepts that apply to any IaC framework. Currently reads from `.iac.native.terraform.*` but could later support `.iac.native.pulumi.*` etc.
- **`policies/terraform`** — Terraform-specific guardrails: provider version pinning, module version pinning, remote backend. These concepts don't transfer to other IaC tools.

### Related but Separate: `iac-scan` Policy

The `brandon/security-policies` branch already has an `iac-scan` policy that checks whether IaC *security scanning tools* (Checkov, tfsec, Trivy) have been executed. That reads from `.iac_scan.*` and is about security scanner integration. The work here is about *configuration validation and best practices* — parsing the actual Terraform files. These are complementary, not overlapping.

---

## Pre-Implementation Steps

1. Pull latest `lunar-lib` main
2. Read `ai-context/` docs:
   - `component-json/cat-iac.md` — canonical `.iac` schema
   - `component-json/conventions.md` — design principles, especially the IaC/native data example
   - `collector-reference.md` — collector patterns
   - `policy-reference.md` — policy patterns
3. Create a git worktree: `git worktree add ../lunar-lib-wt-terraform -b brandon/terraform`

---

## Part 1: Terraform Collector (`collectors/terraform`)

### File Structure

```
collectors/terraform/
├── assets/
│   └── terraform.svg          # Grayscale SVG icon
├── Earthfile                  # Custom image with hcl2json
├── lunar-collector.yml        # Collector manifest
├── main.sh                    # Main entry point (thin — just parse HCL)
└── README.md                  # Standard collector README
```

No helper scripts. The collector is deliberately thin.

### What the Collector Writes

The collector writes three things:

**1. File validity — `.iac.files[]`**
```json
[
  {"path": "main.tf", "valid": true},
  {"path": "broken.tf", "valid": false, "error": "unexpected token..."}
]
```

**2. Full parsed HCL — `.iac.native.terraform.files[]`**

This is the raw `hcl2json` output per file, which policies analyze in Python:
```json
[
  {
    "path": "main.tf",
    "hcl": {
      "resource": {
        "aws_db_instance": { "main": [{ ... }] },
        "aws_lb": { "api": [{ "internal": false, ... }] }
      },
      "terraform": [{ "required_providers": [{ "aws": { "version": "~> 5.0" } }] }],
      "module": { "vpc": [{ "source": "terraform-aws-modules/vpc/aws", "version": "5.1.0" }] }
    }
  }
]
```

This follows the pattern from `conventions.md:330-357`:
```json
{
  "iac": {
    "native": {
      "terraform": {
        "files": [
          { "path": "main.tf", "hcl": { /* parsed HCL as JSON */ } }
        ]
      }
    }
  }
}
```

**3. Source metadata — `.iac.source`**
```json
{"tool": "hcl2json", "version": "0.6.4"}
```

That's it. No analysis, no resource classification, no WAF/datastore detection.

### `lunar-collector.yml`

```yaml
version: 0

name: terraform
description: Parses Terraform HCL files and collects IaC configuration data
author: earthly

default_image: earthly/lunar-lib:terraform-main

landing_page:
  display_name: "Terraform Collector"
  long_description: |
    Parse Terraform HCL files to extract configuration data. Writes file validity
    and full parsed HCL JSON for downstream policy analysis of providers, modules,
    backends, resources, and infrastructure security posture.
  categories: ["infrastructure", "iac"]
  icon: "assets/terraform.svg"
  status: "stable"
  related:
    - slug: "iac"
      type: "policy"
      reason: "Enforces generic IaC best practices using this collector's data"
    - slug: "terraform"
      type: "policy"
      reason: "Enforces Terraform-specific best practices using this collector's data"

collectors:
  - name: terraform
    description: |
      Parses all Terraform (.tf) files in the repository using hcl2json and collects:
      - File validity and parse errors (.iac.files[])
      - Full parsed HCL JSON for policy analysis (.iac.native.terraform.files[])
      - Source tool metadata (.iac.source)
    mainBash: main.sh
    hook:
      type: code
    keywords: ["terraform", "iac", "infrastructure", "hcl", "aws", "providers", "modules"]

example_component_json: |
  {
    "iac": {
      "source": {
        "tool": "hcl2json",
        "version": "0.6.4"
      },
      "files": [
        {"path": "main.tf", "valid": true},
        {"path": "variables.tf", "valid": true}
      ],
      "native": {
        "terraform": {
          "files": [
            {
              "path": "main.tf",
              "hcl": {
                "resource": {
                  "aws_db_instance": {"main": [{"engine": "postgres"}]},
                  "aws_lb": {"api": [{"internal": false}]}
                },
                "terraform": [{"required_providers": [{"aws": {"version": "~> 5.0"}}]}]
              }
            }
          ]
        }
      }
    }
  }
```

### `Earthfile`

```
VERSION 0.8

image:
    FROM --pass-args ../../+base-image

    # Install hcl2json for Terraform HCL parsing
    ARG TARGETARCH
    ARG HCL2JSON_VERSION=0.6.4
    RUN curl -fsSL -o /usr/local/bin/hcl2json \
        "https://github.com/tmccombs/hcl2json/releases/download/v${HCL2JSON_VERSION}/hcl2json_linux_${TARGETARCH}" && \
        chmod +x /usr/local/bin/hcl2json && \
        echo "${HCL2JSON_VERSION}" > /usr/local/bin/hcl2json.version

    ARG VERSION=main
    SAVE IMAGE --push earthly/lunar-lib:terraform-$VERSION
```

### `main.sh`

Simple — find files, parse, collect. Follow `collectors/dockerfile/main.sh` patterns:

```bash
#!/bin/bash
set -e

# Process a single .tf file — output JSON object with path, validity, and parsed HCL
process_file() {
    local tf_file="$1"
    local rel_path="${tf_file#./}"

    set +e
    hcl_json="$(hcl2json "$tf_file" 2>&1)"
    status=$?
    set -e

    if [ $status -eq 0 ]; then
        # Valid file — include parsed HCL
        jq -n --arg path "$rel_path" --argjson hcl "$hcl_json" \
            '{path: $path, valid: true, hcl: $hcl}'
    else
        # Invalid file — include error
        jq -n --arg path "$rel_path" --arg error "$hcl_json" \
            '{path: $path, valid: false, error: $error}'
    fi
}
export -f process_file

# Find and process all .tf files
tf_files=$(find . -type f -name '*.tf' 2>/dev/null)
if [ -z "$tf_files" ]; then
    exit 0  # No Terraform files — nothing to collect
fi

# Process in parallel, split into validity data and native HCL data
all_results=$(echo "$tf_files" | parallel -j 4 process_file | jq -s '.')

# Write .iac.files[] — just {path, valid, error?}
echo "$all_results" | jq '[.[] | {path, valid} + (if .error then {error} else {} end)]' \
    | lunar collect -j ".iac.files" -

# Write .iac.native.terraform.files[] — {path, hcl} for valid files only
echo "$all_results" | jq '[.[] | select(.valid) | {path, hcl}]' \
    | lunar collect -j ".iac.native.terraform.files" -

# Write source metadata
TOOL_VERSION=$(cat /usr/local/bin/hcl2json.version 2>/dev/null || echo "unknown")
jq -n --arg version "$TOOL_VERSION" '{tool: "hcl2json", version: $version}' \
    | lunar collect -j ".iac.source" -
```

Add `BUILD --pass-args ./collectors/terraform+image` to the root `Earthfile`'s `all:` target.

---

## Part 2: IaC Policy (`policies/iac`)

Generic IaC guardrails — concepts that transfer across Terraform, Pulumi, CloudFormation, etc.

### File Structure

```
policies/iac/
├── assets/
│   └── iac.svg                    # Grayscale SVG icon
├── helpers.py                     # Shared analysis functions (parse TF resources, etc.)
├── valid.py                       # All IaC files parse successfully
├── waf_protection.py              # Internet-facing services have WAF
├── datastore_protection.py        # Datastores have deletion protection
├── lunar-policy.yml               # Policy manifest
├── requirements.txt               # lunar_policy==0.2.1
└── README.md                      # Standard policy README
```

### `lunar-policy.yml`

```yaml
version: 0

name: iac
description: Infrastructure as Code configuration and best practices
author: earthly

default_image: earthly/lunar-lib:base-main

landing_page:
  display_name: "IaC Guardrails"
  long_description: |
    Enforce Infrastructure as Code best practices including configuration validity,
    WAF protection for internet-facing services, and datastore deletion protection.
    Works with any IaC collector that writes to the .iac schema.
  category: "deployment-and-infrastructure"
  icon: "assets/iac.svg"
  status: "stable"
  requires:
    - slug: "terraform"
      type: "collector"
      reason: "Provides parsed IaC configuration data"
  related:
    - slug: "terraform"
      type: "policy"
      reason: "Terraform-specific guardrails (providers, modules, backend)"
    - slug: "iac-scan"
      type: "policy"
      reason: "Complements configuration checks with security scanning"

policies:
  - name: valid
    description: |
      Validates that all IaC configuration files are syntactically correct.
      Invalid configurations will fail deployment.
    mainPython: valid.py
    keywords: ["iac", "terraform", "syntax", "validation", "hcl"]

  - name: waf-protection
    description: |
      Requires WAF protection for internet-facing services.
      Analyzes IaC resources to detect public load balancers, API gateways,
      and CloudFront distributions, then verifies WAF association.
    mainPython: waf_protection.py
    keywords: ["iac", "waf", "security", "internet facing", "load balancer"]

  - name: datastore-protection
    description: |
      Requires deletion protection on datastores (databases, storage, caches).
      Prevents accidental data loss from destroy operations or resource replacement.
    mainPython: datastore_protection.py
    keywords: ["iac", "datastores", "deletion protection", "data safety", "prevent_destroy"]

inputs:
  datastore_types:
    description: |
      Comma-separated list of Terraform resource types considered datastores.
    default: "aws_s3_bucket,aws_db_instance,aws_dynamodb_table,aws_elasticache_cluster,aws_elasticache_replication_group,aws_ebs_volume,aws_efs_file_system"
```

### `helpers.py` — Shared Analysis Functions

The analysis that was in the meridian collector's bash helpers moves here as Python:

```python
"""Shared analysis functions for IaC policies.

These functions analyze .iac.native.terraform.files[].hcl data to extract
infrastructure properties. Currently supports Terraform; can be extended
for other IaC tools.
"""

# Resource types that indicate internet accessibility
INTERNET_FACING_CHECKS = {
    "aws_lb": lambda cfg: any(
        inst.get("scheme") == "internet-facing"
        for instances in cfg.values() for inst in instances
    ),
    "aws_elb": lambda cfg: any(
        not inst.get("internal", False)
        for instances in cfg.values() for inst in instances
    ),
    "aws_api_gateway_rest_api": lambda cfg: len(cfg) > 0,
    "aws_apigatewayv2_api": lambda cfg: len(cfg) > 0,
    "aws_cloudfront_distribution": lambda cfg: len(cfg) > 0,
}

WAF_INDICATORS = {
    "aws_wafv2_web_acl": lambda cfg: len(cfg) > 0,
    "aws_wafv2_web_acl_association": lambda cfg: len(cfg) > 0,
}

DEFAULT_DATASTORE_TYPES = [
    "aws_s3_bucket", "aws_db_instance", "aws_dynamodb_table",
    "aws_elasticache_cluster", "aws_elasticache_replication_group",
    "aws_ebs_volume", "aws_efs_file_system",
]


def get_all_resources(native_files_node):
    """Yield (resource_type, name, config) tuples from all parsed TF files."""
    if not native_files_node.exists():
        return
    for f in native_files_node:
        hcl = f.get_node(".hcl")
        if not hcl.exists():
            continue
        resources = hcl.get_node(".resource")
        if not resources.exists():
            continue
        # resources is {resource_type: {name: [config]}}
        raw = resources.get_value()
        if isinstance(raw, dict):
            for rtype, instances in raw.items():
                if isinstance(instances, dict):
                    for name, configs in instances.items():
                        yield rtype, name, configs


def is_internet_accessible(native_files_node):
    """Check if any resources indicate internet accessibility."""
    for rtype, name, configs in get_all_resources(native_files_node):
        checker = INTERNET_FACING_CHECKS.get(rtype)
        if checker and checker({name: configs}):
            return True
    return False


def has_waf_protection(native_files_node):
    """Check if WAF resources are configured."""
    has_waf = False
    has_association = False
    for rtype, name, configs in get_all_resources(native_files_node):
        if rtype == "aws_wafv2_web_acl":
            has_waf = True
        if rtype == "aws_wafv2_web_acl_association":
            has_association = True
    return has_waf and has_association


def check_datastores(native_files_node, datastore_types=None):
    """Check datastores for deletion protection.
    
    Returns: (count, all_protected, unprotected_names)
    """
    if datastore_types is None:
        datastore_types = DEFAULT_DATASTORE_TYPES
    
    count = 0
    unprotected = []
    
    for rtype, name, configs in get_all_resources(native_files_node):
        if rtype not in datastore_types:
            continue
        count += 1
        # Check lifecycle.prevent_destroy
        protected = False
        if isinstance(configs, list):
            for cfg in configs:
                lifecycle = cfg.get("lifecycle", [])
                if isinstance(lifecycle, list) and lifecycle:
                    if lifecycle[0].get("prevent_destroy", False):
                        protected = True
        if not protected:
            unprotected.append(f"{rtype}.{name}")
    
    return count, len(unprotected) == 0, unprotected
```

### Policy Implementations

**`valid.py`**
```python
from lunar_policy import Check

def main(node=None):
    c = Check("valid", "IaC configuration files are valid", node=node)
    with c:
        files = c.get_node(".iac.files")
        if not files.exists():
            return c  # No IaC files — skip
        for f in files:
            if not f.get_value_or_default(".valid", True):
                path = f.get_value_or_default(".path", "unknown")
                error = f.get_value_or_default(".error", "syntax error")
                c.fail(f"{path}: {error}")
    return c

if __name__ == "__main__":
    main()
```

**`waf_protection.py`**
```python
from lunar_policy import Check
from helpers import is_internet_accessible, has_waf_protection

def main(node=None):
    c = Check("waf-protection", "Internet-facing services have WAF", node=node)
    with c:
        native = c.get_node(".iac.native.terraform.files")
        if not native.exists():
            return c  # No Terraform data — skip
        
        if is_internet_accessible(native):
            c.assert_true(
                has_waf_protection(native),
                "Service has internet-facing resources but no WAF protection configured"
            )
    return c

if __name__ == "__main__":
    main()
```

**`datastore_protection.py`**
```python
from lunar_policy import Check, variable_or_default
from helpers import check_datastores, DEFAULT_DATASTORE_TYPES

def main(node=None):
    c = Check("datastore-protection", "Datastores have deletion protection", node=node)
    with c:
        native = c.get_node(".iac.native.terraform.files")
        if not native.exists():
            return c  # No Terraform data — skip
        
        # Parse configurable datastore types
        ds_types_str = variable_or_default("datastore_types", "")
        if ds_types_str:
            ds_types = [t.strip() for t in ds_types_str.split(",") if t.strip()]
        else:
            ds_types = DEFAULT_DATASTORE_TYPES
        
        count, all_protected, unprotected = check_datastores(native, ds_types)
        if count == 0:
            return c  # No datastores — skip
        
        if not all_protected:
            c.fail(
                f"Datastores without deletion protection: {', '.join(unprotected)}. "
                "Add lifecycle { prevent_destroy = true } to protect against accidental deletion."
            )
    return c

if __name__ == "__main__":
    main()
```

---

## Part 3: Terraform Policy (`policies/terraform`)

Terraform-specific guardrails — concepts that don't transfer to other IaC frameworks.

### File Structure

```
policies/terraform/
├── assets/
│   └── terraform.svg                  # Grayscale SVG icon (can reuse collector's)
├── helpers.py                         # Shared Terraform-specific extraction
├── provider_versions_pinned.py        # Provider version constraints
├── module_versions_pinned.py          # Module versions are pinned
├── remote_backend.py                  # Remote backend configured
├── lunar-policy.yml                   # Policy manifest
├── requirements.txt                   # lunar_policy==0.2.1
└── README.md                          # Standard policy README
```

### `lunar-policy.yml`

```yaml
version: 0

name: terraform
description: Terraform-specific configuration and best practices
author: earthly

default_image: earthly/lunar-lib:base-main

landing_page:
  display_name: "Terraform Guardrails"
  long_description: |
    Enforce Terraform-specific best practices including provider version pinning,
    module version pinning, and remote backend configuration.
  category: "deployment-and-infrastructure"
  icon: "assets/terraform.svg"
  status: "stable"
  requires:
    - slug: "terraform"
      type: "collector"
      reason: "Provides parsed Terraform HCL data"
  related:
    - slug: "iac"
      type: "policy"
      reason: "Generic IaC guardrails (validity, WAF, datastores)"

policies:
  - name: provider-versions-pinned
    description: |
      Requires Terraform providers to specify version constraints in required_providers.
      Unpinned providers can introduce breaking changes unexpectedly.
    mainPython: provider_versions_pinned.py
    keywords: ["terraform", "providers", "version pinning", "reproducibility"]

  - name: module-versions-pinned
    description: |
      Requires Terraform modules to use pinned versions or commit SHAs.
      Unpinned modules make infrastructure deployments non-reproducible.
    mainPython: module_versions_pinned.py
    keywords: ["terraform", "modules", "version pinning", "reproducibility"]

  - name: remote-backend
    description: |
      Requires Terraform to use a remote backend for state management.
      Local state files are fragile and cannot be shared across teams.
    mainPython: remote_backend.py
    keywords: ["terraform", "backend", "state management", "s3", "gcs", "terraform cloud"]

inputs:
  required_backend_types:
    description: Comma-separated list of approved backend types (empty = any remote backend)
    default: ""
```

### `helpers.py` — Terraform-Specific Extraction

```python
"""Extract Terraform-specific configuration from parsed HCL."""


def get_providers(native_files_node):
    """Extract provider version constraints from required_providers blocks.
    
    Returns: list of {name, version_constraint, is_pinned}
    """
    providers = {}
    if not native_files_node.exists():
        return []
    
    for f in native_files_node:
        hcl = f.get_node(".hcl")
        if not hcl.exists():
            continue
        raw = hcl.get_value()
        # terraform[].required_providers[].{provider: {version: "..."}}
        for tf_block in raw.get("terraform", []):
            for rp_block in tf_block.get("required_providers", []):
                for name, config in rp_block.items():
                    version = None
                    if isinstance(config, dict):
                        version = config.get("version")
                    elif isinstance(config, str):
                        version = config
                    providers[name] = version
    
    return [
        {"name": name, "version_constraint": vc, "is_pinned": vc is not None}
        for name, vc in providers.items()
    ]


def get_modules(native_files_node):
    """Extract module sources and version pinning.
    
    Returns: list of {name, source, version, is_pinned}
    """
    modules = []
    if not native_files_node.exists():
        return []
    
    for f in native_files_node:
        hcl = f.get_node(".hcl")
        if not hcl.exists():
            continue
        raw = hcl.get_value()
        for mod_name, mod_configs in raw.get("module", {}).items():
            if isinstance(mod_configs, list):
                for cfg in mod_configs:
                    source = cfg.get("source", "")
                    version = cfg.get("version")
                    # Pinned if has explicit version, or source contains ref= or commit hash
                    is_pinned = (
                        version is not None
                        or "?ref=" in source
                        or "//" in source and "?ref=" in source
                    )
                    modules.append({
                        "name": mod_name,
                        "source": source,
                        "version": version,
                        "is_pinned": is_pinned,
                    })
    return modules


def get_backend(native_files_node):
    """Extract backend configuration.
    
    Returns: {type, configured} or None
    """
    if not native_files_node.exists():
        return None
    
    for f in native_files_node:
        hcl = f.get_node(".hcl")
        if not hcl.exists():
            continue
        raw = hcl.get_value()
        for tf_block in raw.get("terraform", []):
            backends = tf_block.get("backend", [])
            if isinstance(backends, list):
                for backend in backends:
                    if isinstance(backend, dict):
                        for backend_type in backend:
                            return {"type": backend_type, "configured": True}
            elif isinstance(backends, dict):
                for backend_type in backends:
                    return {"type": backend_type, "configured": True}
    return None
```

### Policy Implementations

**`provider_versions_pinned.py`**
```python
from lunar_policy import Check
from helpers import get_providers

def main(node=None):
    c = Check("provider-versions-pinned", "Terraform providers have version constraints", node=node)
    with c:
        native = c.get_node(".iac.native.terraform.files")
        if not native.exists():
            return c
        
        providers = get_providers(native)
        if not providers:
            return c  # No providers — skip
        
        unpinned = [p["name"] for p in providers if not p["is_pinned"]]
        if unpinned:
            c.fail(
                f"Providers without version constraints: {', '.join(unpinned)}. "
                "Add version constraints in required_providers to ensure reproducible deployments."
            )
    return c

if __name__ == "__main__":
    main()
```

**`module_versions_pinned.py`**
```python
from lunar_policy import Check
from helpers import get_modules

def main(node=None):
    c = Check("module-versions-pinned", "Terraform modules have pinned versions", node=node)
    with c:
        native = c.get_node(".iac.native.terraform.files")
        if not native.exists():
            return c
        
        modules = get_modules(native)
        if not modules:
            return c  # No modules — skip
        
        unpinned = [m["name"] for m in modules if not m["is_pinned"]]
        if unpinned:
            c.fail(
                f"Modules without pinned versions: {', '.join(unpinned)}. "
                "Add version constraints or use ?ref= to pin module sources."
            )
    return c

if __name__ == "__main__":
    main()
```

**`remote_backend.py`**
```python
from lunar_policy import Check, variable_or_default
from helpers import get_backend

def main(node=None):
    c = Check("remote-backend", "Terraform uses a remote backend", node=node)
    with c:
        native = c.get_node(".iac.native.terraform.files")
        if not native.exists():
            return c
        
        backend = get_backend(native)
        if backend is None:
            c.fail("No backend configured. Terraform state is stored locally, "
                   "which is fragile and cannot be shared across teams.")
            return c
        
        # Check approved types if configured
        approved_str = variable_or_default("required_backend_types", "")
        if approved_str:
            approved = [t.strip() for t in approved_str.split(",") if t.strip()]
            if backend["type"] not in approved:
                c.fail(f"Backend type '{backend['type']}' is not in approved list: {', '.join(approved)}")
    return c

if __name__ == "__main__":
    main()
```

---

## Part 4: Testing

### Test Components

| Component | Has `.tf` files? | Expected Behavior |
|---|---|---|
| `meridian-demo/ctlstore` | Yes | Full `.iac` data, all policy checks execute |
| `meridian-demo/backend` | No | Collector exits cleanly, no `.iac` data, all policies SKIP |
| `pantalasa-cronos/backend` | No | SKIP |

### Edge Cases to Verify

1. **No `.tf` files** — collector exits 0, no data written, all policies skip gracefully
2. **Invalid `.tf` file** — `.iac.files[]` has `valid: false` with error, `valid` policy FAILS
3. **Datastores without `prevent_destroy`** — `datastore-protection` FAILS with resource names
4. **Internet-facing LB without WAF** — `waf-protection` FAILS
5. **Providers without version constraints** — `provider-versions-pinned` FAILS with provider names
6. **Modules without pinned versions** — `module-versions-pinned` FAILS with module names

### Testing Commands

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar

# Reference worktree in lunar-config.yml:
#   - uses: ../lunar-lib-wt-terraform/collectors/terraform
#   - uses: ../lunar-lib-wt-terraform/policies/iac
#   - uses: ../lunar-lib-wt-terraform/policies/terraform

# Test collector
lunar collector dev terraform.terraform --component github.com/meridian-demo/ctlstore --verbose

# Test iac policy
lunar policy dev iac.valid --component github.com/meridian-demo/ctlstore --verbose
lunar policy dev iac.waf-protection --component github.com/meridian-demo/ctlstore --verbose
lunar policy dev iac.datastore-protection --component github.com/meridian-demo/ctlstore --verbose

# Test terraform policy
lunar policy dev terraform.provider-versions-pinned --component github.com/meridian-demo/ctlstore --verbose
lunar policy dev terraform.module-versions-pinned --component github.com/meridian-demo/ctlstore --verbose
lunar policy dev terraform.remote-backend --component github.com/meridian-demo/ctlstore --verbose
```

---

## Part 5: Assets (SVG Icons)

Create grayscale SVG icons:
- `collectors/terraform/assets/terraform.svg` — Terraform logo in grayscale
- `policies/iac/assets/iac.svg` — Generic IaC/infrastructure icon in grayscale
- `policies/terraform/assets/terraform.svg` — Same or similar to collector's icon

**Important:** SVGs must be grayscale only — the website flattens RGB colors. Validate with `scripts/validate_svg_grayscale.py`.

---

## Part 6: Update Meridian Config

After merging to main (or using branch ref), update `meridian/lunar/lunar-config.yml`:

```yaml
# Collector — replace local with lunar-lib
  - uses: github://earthly/lunar-lib/collectors/terraform@main
    on: ["domain:engineering"]

# Policies — replace single local policy with two lunar-lib policies
  - uses: github://earthly/lunar-lib/policies/iac@main
    name: iac
    description: IaC configuration best practices
    initiative: good-practices
    enforcement: report-pr
    on: ["domain:engineering"]

  - uses: github://earthly/lunar-lib/policies/terraform@main
    name: terraform
    description: Terraform-specific best practices
    initiative: good-practices
    enforcement: report-pr
    on: ["domain:engineering"]
```

**Note:** Check names change — old `terraform-valid`/`terraform-has-waf`/`terraform-has-delete-protection` become `iac.valid`/`iac.waf-protection`/`iac.datastore-protection` plus new `terraform.provider-versions-pinned`/`terraform.module-versions-pinned`/`terraform.remote-backend`.

---

## Part 7: PR & Review

1. Push branch `brandon/terraform`
2. Create draft PR with title: `Add terraform collector and iac/terraform policies`
3. PR description should explain:
   - What's imported from meridian and what's new
   - Design: thin collector (just HCL parsing), smart policies (analysis in Python)
   - Two policies: `iac` (generic) + `terraform` (Terraform-specific)
   - Relationship to existing `iac-scan` policy
4. Run `@coderabbitai review`
5. Add `BUILD --pass-args ./collectors/terraform+image` to root Earthfile `all:` target
