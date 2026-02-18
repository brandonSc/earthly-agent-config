# Terraform Collector & IaC Policy — Implementation Plan

Import the Terraform collector and corresponding policies from `meridian/lunar/` into `lunar-lib` as first-class plugins.

---

## Context

The meridian demo environment has a working Terraform collector and policy at:
- `meridian/lunar/collectors/terraform/` — parses `.tf` files with `hcl2json`, detects internet accessibility, WAF protection, and datastore deletion protection
- `meridian/lunar/policies/terraform/` — three checks: `terraform-valid`, `terraform-has-waf`, `terraform-has-delete-protection`

These currently write to `.terraform.*` paths, but the canonical Component JSON schema defines `.iac.*` for Infrastructure as Code data (see `ai-context/component-json/cat-iac.md`).

### Related but Separate: `iac-scan` Policy

The `brandon/security-policies` branch already has an `iac-scan` policy that checks whether IaC *security scanning tools* (Checkov, tfsec, Trivy) have been executed. That reads from `.iac_scan.*` and is about security scanner integration. The terraform/iac work here is about *configuration validation* — parsing the actual Terraform files and enforcing best practices. These are complementary, not overlapping.

---

## Pre-Implementation Steps

1. Pull latest `lunar-lib` main
2. Read `ai-context/` docs:
   - `component-json/cat-iac.md` — canonical `.iac` schema
   - `component-json/conventions.md` — design principles
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
├── main.sh                    # Main entry point
├── check_internet_access.sh   # Helper: internet accessibility detection
├── check_waf.sh               # Helper: WAF protection detection
├── check_datastores.sh        # Helper: datastore + deletion protection
├── check_providers.sh         # NEW: provider version pinning detection
├── check_modules.sh           # NEW: module version pinning detection
├── check_backend.sh           # NEW: remote backend detection
└── README.md                  # Standard collector README
```

### Key Changes from Meridian Version

**Schema migration: `.terraform.*` → `.iac.*`**

The collector must write to the canonical `.iac` schema:

| Meridian Path | lunar-lib Path | Notes |
|---|---|---|
| `.terraform.files[]` | `.iac.files[]` | Rename, keep `{path, valid, error}` |
| `.terraform.is_internet_accessible` | `.iac.analysis.internet_accessible` | Move to `.analysis` object |
| `.terraform.has_waf_protection` | `.iac.analysis.has_waf` | Move to `.analysis` object |
| `.terraform.has_datastores` | `.iac.datastores.count > 0` | Replace boolean with count |
| `.terraform.has_datastore_protection` | `.iac.datastores.all_deletion_protected` | Rename |
| `.terraform.unprotected_datastores` | `.iac.datastores.unprotected[]` | Rename |
| *(new)* | `.iac.source` | `{tool: "hcl2json", version: "..."}` |
| *(new)* | `.iac.providers[]` | `{name, version_constraint, is_pinned}` |
| *(new)* | `.iac.modules[]` | `{source, version, is_pinned}` |
| *(new)* | `.iac.analysis.has_backend` | Remote backend configured |
| *(new)* | `.iac.analysis.versions_pinned` | All provider versions pinned |
| *(new)* | `.iac.resources[]` | Normalized resource list |
| *(new)* | `.iac.summary` | `{all_valid, resource_count}` |
| *(new)* | `.iac.native.terraform.files[]` | Raw HCL JSON per file |

**Don't dump full HCL JSON into `.iac.files[]`** — the meridian version puts the entire parsed HCL in `json_content` for each file. Instead, put normalized data in `.iac.files[]` and full HCL in `.iac.native.terraform.files[]` for advanced use.

### `lunar-collector.yml`

```yaml
version: 0

name: terraform
description: Parses Terraform files and collects IaC configuration metadata
author: earthly

default_image: earthly/lunar-lib:terraform-main

landing_page:
  display_name: "Terraform Collector"
  long_description: |
    Parse Terraform HCL files to extract configuration metadata including provider
    versions, module sources, backend configuration, resource inventory, and
    infrastructure analysis (internet accessibility, WAF, datastore protection).
  categories: ["infrastructure", "iac"]
  icon: "assets/terraform.svg"
  status: "stable"
  related:
    - slug: "iac"
      type: "policy"
      reason: "Enforces IaC best practices using this collector's data"
    - slug: "k8s"
      type: "collector"
      reason: "Components may also have Kubernetes manifests alongside Terraform"

collectors:
  - name: terraform
    description: |
      Parses all Terraform (.tf) files in the repository using hcl2json and collects:
      - File validity and parse errors
      - Provider version constraints
      - Module sources and version pinning
      - Backend configuration
      - Resource inventory with normalized types
      - Infrastructure analysis (internet accessibility, WAF, datastore protection)
    mainBash: main.sh
    hook:
      type: code
    keywords: ["terraform", "iac", "infrastructure", "hcl", "aws", "providers", "modules"]

inputs:
  datastore_types:
    description: |
      Space-separated list of Terraform resource types considered datastores.
      Used for deletion protection checks.
    default: "aws_s3_bucket aws_db_instance aws_dynamodb_table aws_elasticache_cluster aws_elasticache_replication_group aws_ebs_volume aws_efs_file_system aws_secretsmanager_secret aws_ssm_parameter aws_cloudwatch_log_group"

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
      "providers": [
        {"name": "aws", "version_constraint": "~> 5.0", "is_pinned": true},
        {"name": "random", "version_constraint": null, "is_pinned": false}
      ],
      "modules": [
        {"source": "terraform-aws-modules/vpc/aws", "version": "5.1.0", "is_pinned": true}
      ],
      "backend": {
        "type": "s3",
        "configured": true
      },
      "resources": [
        {
          "type": "database",
          "provider": "aws",
          "resource_type": "aws_db_instance",
          "name": "main",
          "path": "database.tf",
          "deletion_protected": true
        }
      ],
      "analysis": {
        "has_backend": true,
        "versions_pinned": false,
        "internet_accessible": true,
        "has_waf": true
      },
      "datastores": {
        "count": 2,
        "all_deletion_protected": true,
        "unprotected": []
      },
      "summary": {
        "all_valid": true,
        "resource_count": 12
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

### `main.sh` Refactoring

The main script should:

1. Find all `.tf` files
2. Parse each with `hcl2json` — write validity to `.iac.files[]`
3. Store full parsed HCL in `.iac.native.terraform.files[]` for advanced policy use
4. Extract providers → `.iac.providers[]`
5. Extract modules → `.iac.modules[]`
6. Extract backend → `.iac.backend`
7. Build resource inventory → `.iac.resources[]`
8. Run analysis helpers (internet access, WAF, datastores) → `.iac.analysis`, `.iac.datastores`
9. Compute summary → `.iac.summary`
10. Write source metadata → `.iac.source`

**Important patterns to follow** (from `collectors/dockerfile/main.sh`):
- Use `parallel -j 4` for file processing
- Use `export -f` for functions called by parallel
- Read `LUNAR_VAR_*` env vars for inputs
- Write source metadata including tool version

### Helper Scripts

Refactor from meridian with these changes:
- `check_internet_access.sh` — same logic, output structured JSON
- `check_waf.sh` — same logic, output structured JSON  
- `check_datastores.sh` — read `LUNAR_VAR_DATASTORE_TYPES` instead of hardcoded list; output `{count, all_deletion_protected, unprotected: []}` structure
- `check_providers.sh` (NEW) — parse `required_providers` blocks, extract version constraints
- `check_modules.sh` (NEW) — parse `module` blocks, check for version or ref pinning
- `check_backend.sh` (NEW) — parse `terraform { backend {} }` blocks

---

## Part 2: IaC Policy (`policies/iac`)

### File Structure

```
policies/iac/
├── assets/
│   └── iac.svg                    # Grayscale SVG icon
├── valid.py                       # All IaC files parse successfully
├── provider_versions_pinned.py    # Provider version constraints exist
├── module_versions_pinned.py      # Module versions are pinned
├── remote_backend.py              # Remote backend is configured
├── waf_protection.py              # Internet-facing services have WAF
├── datastore_protection.py        # Datastores have deletion protection
├── lunar-policy.yml               # Policy manifest
├── requirements.txt               # Python dependencies
└── README.md                      # Standard policy README
```

### Why `iac` not `terraform`

Following the `dockerfile` → `container` pattern: the collector is tool-specific (`terraform`) but the policy is capability-specific (`iac`). This means if we add a Pulumi or CloudFormation collector later, it can write to the same `.iac.*` schema and the same policy works.

### Policy Checks

| Check Name | Description | Component JSON Paths | Inputs |
|---|---|---|---|
| `valid` | All IaC files are syntactically valid | `.iac.files[].valid`, `.iac.summary.all_valid` | — |
| `provider-versions-pinned` | Providers specify version constraints | `.iac.providers[].is_pinned`, `.iac.analysis.versions_pinned` | — |
| `module-versions-pinned` | Modules use pinned versions | `.iac.modules[].is_pinned` | — |
| `remote-backend` | Remote backend configured for state | `.iac.analysis.has_backend` | `required_backend_types` |
| `waf-protection` | Internet-facing services have WAF | `.iac.analysis.internet_accessible`, `.iac.analysis.has_waf` | — |
| `datastore-protection` | Datastores have deletion protection | `.iac.datastores.all_deletion_protected`, `.iac.datastores.unprotected[]` | — |

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
    provider version pinning, module version pinning, remote backend usage,
    WAF protection for internet-facing services, and datastore deletion protection.
  category: "deployment-and-infrastructure"
  icon: "assets/iac.svg"
  status: "stable"
  requires:
    - slug: "terraform"
      type: "collector"
      reason: "Provides parsed IaC configuration data"
  related:
    - slug: "iac-scan"
      type: "policy"
      reason: "Complements IaC configuration checks with security scanning"

policies:
  - name: valid
    description: |
      Validates that all IaC configuration files are syntactically correct.
      Invalid configurations will fail deployment.
    mainPython: valid.py
    keywords: ["iac", "terraform", "syntax", "validation", "hcl"]

  - name: provider-versions-pinned
    description: |
      Requires IaC providers to specify version constraints.
      Unpinned providers can introduce breaking changes unexpectedly.
    mainPython: provider_versions_pinned.py
    keywords: ["iac", "terraform", "providers", "version pinning", "reproducibility"]

  - name: module-versions-pinned
    description: |
      Requires IaC modules to use pinned versions (version constraints or commit SHAs).
      Unpinned modules make builds non-reproducible.
    mainPython: module_versions_pinned.py
    keywords: ["iac", "terraform", "modules", "version pinning"]

  - name: remote-backend
    description: |
      Requires a remote backend for IaC state management.
      Local state files are fragile and cannot be shared across teams.
    mainPython: remote_backend.py
    keywords: ["iac", "terraform", "backend", "state management", "s3", "gcs"]

  - name: waf-protection
    description: |
      Requires WAF protection for internet-facing services.
      Internet-accessible resources without WAF are vulnerable to web attacks.
    mainPython: waf_protection.py
    keywords: ["iac", "terraform", "waf", "security", "internet facing"]

  - name: datastore-protection
    description: |
      Requires deletion protection on datastores (databases, storage, caches).
      Prevents accidental data loss from terraform destroy or resource replacement.
    mainPython: datastore_protection.py
    keywords: ["iac", "terraform", "datastores", "deletion protection", "data safety"]

inputs:
  required_backend_types:
    description: Comma-separated list of approved backend types (empty = any remote backend)
    default: ""
```

### Example Policy Implementations

**`valid.py`** — simple, modeled after `k8s/valid.py`:
```python
from lunar_policy import Check

def main(node=None):
    c = Check("valid", "IaC configuration files are valid", node=node)
    with c:
        # Check summary field first
        summary = c.get_node(".iac.summary")
        if summary.exists():
            c.assert_true(
                summary.get_value_or_default(".all_valid", True),
                "One or more IaC files have syntax errors"
            )
            return c
        
        # Fall back to iterating files
        files = c.get_node(".iac.files")
        if not files.exists():
            return c  # No IaC files = nothing to check
        
        for f in files:
            if not f.get_value_or_default(".valid", True):
                path = f.get_value_or_default(".path", "unknown")
                error = f.get_value_or_default(".error", "syntax error")
                c.fail(f"{path}: {error}")
    return c

if __name__ == "__main__":
    main()
```

**`waf_protection.py`** — conditional check:
```python
from lunar_policy import Check

def main(node=None):
    c = Check("waf-protection", "Internet-facing services have WAF", node=node)
    with c:
        analysis = c.get_node(".iac.analysis")
        if not analysis.exists():
            return c  # No analysis data
        
        internet_accessible = analysis.get_value_or_default(".internet_accessible", False)
        if internet_accessible:
            c.assert_true(
                analysis.get_value_or_default(".has_waf", False),
                "Service is internet-accessible but has no WAF protection configured"
            )
    return c

if __name__ == "__main__":
    main()
```

**`datastore_protection.py`** — with unprotected resource details:
```python
from lunar_policy import Check

def main(node=None):
    c = Check("datastore-protection", "Datastores have deletion protection", node=node)
    with c:
        ds = c.get_node(".iac.datastores")
        if not ds.exists():
            return c  # No datastores detected
        
        count = ds.get_value_or_default(".count", 0)
        if count == 0:
            return c  # No datastores = nothing to check
        
        if not ds.get_value_or_default(".all_deletion_protected", True):
            unprotected = ds.get_node(".unprotected")
            if unprotected.exists():
                names = [u.get_value() for u in unprotected]
                c.fail(f"Datastores without deletion protection: {', '.join(names)}. "
                       "Add lifecycle {{ prevent_destroy = true }}.")
            else:
                c.fail("One or more datastores lack deletion protection")
    return c

if __name__ == "__main__":
    main()
```

---

## Part 3: Testing

### Test Components

| Component | Expected Behavior |
|---|---|
| `meridian-demo/backend` | No `.tf` files → collector exits cleanly, no `.iac` data, all policies SKIP |
| `meridian-demo/ctlstore` | Has Terraform files → expect `.iac` data, check policies |
| `pantalasa-cronos/backend` | No `.tf` files → SKIP |

**Edge cases to verify:**
1. Component with no `.tf` files at all — collector should exit cleanly, policies should skip gracefully
2. Component with invalid `.tf` files — `valid` check should FAIL with file path and error
3. Component with datastores but no `prevent_destroy` — `datastore-protection` should FAIL with resource names

### Testing Commands

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar

# Test collector (use relative path to worktree)
lunar collector dev terraform.terraform --component github.com/meridian-demo/ctlstore --verbose

# Test policies individually
lunar policy dev iac.valid --component github.com/meridian-demo/ctlstore --verbose
lunar policy dev iac.waf-protection --component github.com/meridian-demo/ctlstore --verbose
lunar policy dev iac.datastore-protection --component github.com/meridian-demo/ctlstore --verbose
```

---

## Part 4: Assets (SVG Icons)

Create grayscale SVG icons:
- `collectors/terraform/assets/terraform.svg` — Terraform logo in grayscale
- `policies/iac/assets/iac.svg` — Generic IaC icon (infrastructure/cloud) in grayscale

**Important:** SVGs must be grayscale only — the website flattens RGB colors. Validate with `scripts/validate_svg_grayscale.py`.

---

## Part 5: Update Meridian Config

After merging to main (or using branch ref), update `meridian/lunar/lunar-config.yml`:

```yaml
# Before:
  - uses: ./collectors/terraform
    on: ["domain:engineering"]

# After:
  - uses: github://earthly/lunar-lib/collectors/terraform@main
    on: ["domain:engineering"]

# Before:
  - uses: ./policies/terraform
    name: terraform
    ...

# After:
  - uses: github://earthly/lunar-lib/policies/iac@main
    name: iac
    description: IaC configuration best practices
    initiative: good-practices
    enforcement: report-pr
    on: ["domain:engineering"]
```

**Note:** Policy check names change from `terraform-valid` → `valid`, `terraform-has-waf` → `waf-protection`, `terraform-has-delete-protection` → `datastore-protection`. Any dashboards or references to old check names will need updating.

---

## Part 6: PR & Review

1. Push branch `brandon/terraform`
2. Create draft PR with title: `Add terraform collector and iac policy`
3. PR description should explain:
   - What's imported from meridian and what's new
   - Schema mapping (`.terraform.*` → `.iac.*`)
   - New checks added beyond meridian (providers, modules, backend)
   - Relationship to existing `iac-scan` policy
4. Run `@coderabbitai review`
5. Add the Earthfile image target to `all:` in root Earthfile

---

## Open Questions

1. **Should we add the terraform Earthfile image to the `all:` build target?** — Yes, like k8s and dockerfile do. Add `BUILD --pass-args ./collectors/terraform+image` to the root Earthfile's `all:` target.

2. **Should `install.sh` from meridian be kept?** — No. The Earthfile handles installing `hcl2json` into the Docker image. The `install.sh` was for local development without Docker.

3. **The meridian collector uses `parallel` (GNU parallel) — is it in the base image?** — Check if `parallel` is available in `earthly/lunar-lib:base-main`. If not, add it to the terraform Earthfile image, or use `xargs -P 4` as an alternative.

4. **Provider/module/backend extraction adds complexity.** Should we start with just the three existing checks (valid, WAF, datastores) and add provider/module/backend in a follow-up? This is a judgment call — the guardrail specs define them but they require non-trivial HCL parsing.
