# Security Scanning Policies Implementation Plan

Create 4 security scanning policies that enforce scanning and vulnerability thresholds. All follow the same pattern, reading from normalized Component JSON paths written by collectors like Snyk, Semgrep, Trivy, etc.

## Overview

| Policy | Category | Description |
|--------|----------|-------------|
| `sca` | `.sca` | Software Composition Analysis (dependency vulnerabilities) |
| `sast` | `.sast` | Static Application Security Testing (code vulnerabilities) |
| `container-scan` | `.container_scan` | Container image vulnerability scanning |
| `iac-scan` | `.iac_scan` | Infrastructure as Code security scanning |

All policies share the same check structure:
- `executed` — Verify scanner ran (aligns with spec `sec-{category}-executed`)
- `no-critical` — No critical severity findings
- `no-high` — No high severity findings (optional, configurable)
- `max-total` — Total findings under threshold (configurable)

---

## ⚠️ Current Collector Limitations

**Important:** The current Snyk (PR #22) and Semgrep (PR #21) collectors only write **source metadata**, not vulnerability counts. This means:

| Check | Current Status | What's Missing |
|-------|----------------|----------------|
| `executed` | ✅ Works | — |
| `no-critical` | ❌ Will skip | `.{category}.vulnerabilities.critical` or `.summary.has_critical` |
| `no-high` | ❌ Will skip | `.{category}.vulnerabilities.high` or `.summary.has_high` |
| `max-total` | ❌ Will skip | `.{category}.vulnerabilities.total` |

**What collectors currently write:**
```json
{
  "sca": {
    "source": { "tool": "snyk", "integration": "github_app" },
    "native": { "snyk": { ... } }
  }
}
```

**What policies expect:**
```json
{
  "sca": {
    "source": { "tool": "snyk", "integration": "github_app" },
    "vulnerabilities": { "critical": 0, "high": 1, "medium": 3, "total": 12 },
    "summary": { "has_critical": false, "has_high": true }
  }
}
```

**Future enhancements:** The Snyk and Semgrep collectors will need to parse vulnerability counts from:
- **GitHub App**: Check annotations/output (if available in API response)
- **CLI**: JSON output (`snyk test --json`, `semgrep --json`)

**PR Description:** When implementing this policy, note in the PR description that only `executed` is functional until collectors are enhanced. Example:

> **Note:** Currently only the `executed` check is functional. The `no-critical`, `no-high`, and `max-total` checks will skip until the Snyk/Semgrep collectors are enhanced to write vulnerability counts to `.{category}.vulnerabilities.*` paths.

---

## Pre-Implementation

```bash
# 1. Update lunar-lib main
cd /home/brandon/code/earthly/lunar-lib
git checkout main && git pull

# 2. Create worktree
git worktree add ../lunar-lib-wt-security-policies -b brandon/security-policies

# 3. Read the docs
cat ai-context/component-json/cat-sca.md
cat ai-context/component-json/cat-sast.md
cat ai-context/component-json/cat-container-scan.md
cat ai-context/policy-reference.md
```

---

## Implementation

### Directory Structure

Create 4 policy directories with identical structure:

```
lunar-lib-wt-security-policies/policies/
├── sca/
│   ├── lunar-policy.yml
│   ├── executed.py
│   ├── no-critical.py
│   ├── no-high.py
│   ├── max-total.py
│   ├── requirements.txt
│   ├── README.md          # Title must match display_name: "# SCA Guardrails"
│   └── assets/sca.svg
├── sast/
│   └── ... (same structure)
├── container-scan/
│   └── ... (same structure)
└── iac-scan/
    └── ... (same structure)
```

### Policy Pattern (Template)

Each policy follows this pattern. Replace `{CATEGORY}`, `{DISPLAY_NAME}`, and `{DESCRIPTION}` for each:

#### lunar-policy.yml

```yaml
version: 0

name: {POLICY_NAME}
description: {DESCRIPTION}
author: support@earthly.dev

default_image: earthly/lunar-scripts:1.0.0

landing_page:
  display_name: "{DISPLAY_NAME} Guardrails"  # Must end with "Guardrails" per conventions
  long_description: |
    Enforces {DISPLAY_NAME} scanning standards.
    
    Requires a {DISPLAY_NAME} collector (Snyk, Semgrep, etc.) to populate the
    .{CATEGORY} data in the Component JSON.
  category: "security-and-compliance"
  icon: "assets/{POLICY_NAME}.svg"
  status: "stable"
  requires:
    - slug: "snyk"
      type: "collector"
      reason: "Provides {DISPLAY_NAME} data (one option)"
  related: []

policies:
  - name: executed
    description: |
      Verifies that {DISPLAY_NAME} scanning was executed on the component.
      Fails if no scanner has written to .{CATEGORY}.
    mainPython: ./executed.py
    keywords: ["{CATEGORY}", "security", "scanning", "compliance"]

  - name: no-critical
    description: |
      Ensures no critical severity findings exist.
    mainPython: ./no-critical.py
    keywords: ["{CATEGORY}", "critical", "vulnerabilities", "security"]

  - name: no-high
    description: |
      Ensures no high severity findings exist.
    mainPython: ./no-high.py
    keywords: ["{CATEGORY}", "high", "vulnerabilities", "security"]

  - name: max-total
    description: |
      Ensures total findings are under a configurable threshold.
    mainPython: ./max-total.py
    keywords: ["{CATEGORY}", "threshold", "vulnerabilities"]

inputs:
  enforce_no_high:
    description: "Whether to enforce no high severity findings"
    default: "true"
  max_total_threshold:
    description: "Maximum total findings allowed (0 = no limit)"
    default: "0"
```

#### executed.py

```python
from lunar_policy import Check

def check_executed(node=None):
    """Verify {DISPLAY_NAME} scanning was executed."""
    c = Check("executed", "{DISPLAY_NAME} scan must be executed", node=node)
    with c:
        c.assert_exists(".{CATEGORY}", "No {DISPLAY_NAME} scanning data found. Ensure a scanner (Snyk, Semgrep, etc.) is configured.")
    return c

if __name__ == "__main__":
    check_executed()
```

#### no-critical.py

```python
from lunar_policy import Check

def check_no_critical(node=None):
    """Ensure no critical severity findings."""
    c = Check("no-critical", "No critical {CATEGORY_DISPLAY} findings", node=node)
    with c:
        # Skip if no scan data (don't fail components without this scanner type)
        category_node = c.get_node(".{CATEGORY}")
        if not category_node.exists():
            c.skip("No {DISPLAY_NAME} data available")
            return c
        
        # Check summary first (preferred)
        summary = category_node.get_node(".summary.has_critical")
        if summary.exists():
            c.assert_false(summary.get_value(), "Critical {CATEGORY_DISPLAY} findings detected")
            return c
        
        # Fall back to counting
        critical = category_node.get_node(".{FINDINGS_PATH}.critical")
        if critical.exists():
            c.assert_equal(critical.get_value(), 0, "Critical {CATEGORY_DISPLAY} findings detected")
    
    return c

if __name__ == "__main__":
    check_no_critical()
```

#### no-high.py

```python
from lunar_policy import Check, variable_or_default

def check_no_high(node=None):
    """Ensure no high severity findings (if enabled)."""
    c = Check("no-high", "No high severity {CATEGORY_DISPLAY} findings", node=node)
    with c:
        enforce = variable_or_default("enforce_no_high", "true").lower() == "true"
        if not enforce:
            c.skip("High severity check disabled via inputs")
            return c
        
        category_node = c.get_node(".{CATEGORY}")
        if not category_node.exists():
            c.skip("No {DISPLAY_NAME} data available")
            return c
        
        # Check summary first (preferred)
        summary = category_node.get_node(".summary.has_high")
        if summary.exists():
            c.assert_false(summary.get_value(), "High severity {CATEGORY_DISPLAY} findings detected")
            return c
        
        # Fall back to counting
        high = category_node.get_node(".{FINDINGS_PATH}.high")
        if high.exists():
            c.assert_equal(high.get_value(), 0, "High severity {CATEGORY_DISPLAY} findings detected")
    
    return c

if __name__ == "__main__":
    check_no_high()
```

#### max-total.py

```python
from lunar_policy import Check, variable_or_default

def check_max_total(node=None):
    """Ensure total findings under threshold."""
    c = Check("max-total", "Total {CATEGORY_DISPLAY} findings within threshold", node=node)
    with c:
        threshold_str = variable_or_default("max_total_threshold", "0")
        threshold = int(threshold_str)
        
        if threshold == 0:
            c.skip("No maximum threshold configured (set max_total_threshold > 0 to enable)")
            return c
        
        category_node = c.get_node(".{CATEGORY}")
        if not category_node.exists():
            c.skip("No {DISPLAY_NAME} data available")
            return c
        
        total_node = category_node.get_node(".{FINDINGS_PATH}.total")
        if not total_node.exists():
            c.skip("Total findings count not available")
            return c
        
        total_value = total_node.get_value()
        c.assert_less_or_equal(
            total_value, 
            threshold, 
            f"Total {CATEGORY_DISPLAY} findings ({total_value}) exceeds threshold ({threshold})"
        )
    return c

if __name__ == "__main__":
    check_max_total()
```

---

## Policy-Specific Details

### SCA Policy

| Field | Value |
|-------|-------|
| `{POLICY_NAME}` | `sca` |
| `{CATEGORY}` | `sca` |
| `{DISPLAY_NAME}` | `SCA` |
| `{CATEGORY_DISPLAY}` | `vulnerability` |
| `{FINDINGS_PATH}` | `vulnerabilities` |

**Icon:** Use a shield with a package/dependency icon

### SAST Policy

| Field | Value |
|-------|-------|
| `{POLICY_NAME}` | `sast` |
| `{CATEGORY}` | `sast` |
| `{DISPLAY_NAME}` | `SAST` |
| `{CATEGORY_DISPLAY}` | `code` |
| `{FINDINGS_PATH}` | `findings` |

**Icon:** Use a magnifying glass over code

### Container Scan Policy

| Field | Value |
|-------|-------|
| `{POLICY_NAME}` | `container-scan` |
| `{CATEGORY}` | `container_scan` |
| `{DISPLAY_NAME}` | `Container Scan` |
| `{CATEGORY_DISPLAY}` | `container vulnerability` |
| `{FINDINGS_PATH}` | `vulnerabilities` |

**Icon:** Use a container/docker whale with a shield

### IaC Scan Policy

| Field | Value |
|-------|-------|
| `{POLICY_NAME}` | `iac-scan` |
| `{CATEGORY}` | `iac_scan` |
| `{DISPLAY_NAME}` | `IaC Scan` |
| `{CATEGORY_DISPLAY}` | `infrastructure security` |
| `{FINDINGS_PATH}` | `findings` |

**Icon:** Use cloud infrastructure with a shield

---

## Testing

### Test in pantalasa-cronos

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar

# Copy each policy
cp -r /home/brandon/code/earthly/lunar-lib-wt-security-policies/policies/sca ./policies/sca-test
cp -r /home/brandon/code/earthly/lunar-lib-wt-security-policies/policies/sast ./policies/sast-test
cp -r /home/brandon/code/earthly/lunar-lib-wt-security-policies/policies/container-scan ./policies/container-scan-test
cp -r /home/brandon/code/earthly/lunar-lib-wt-security-policies/policies/iac-scan ./policies/iac-scan-test
```

Add to `lunar-config.yml`:

```yaml
policies:
  # SCA - test on components with Snyk
  - uses: ./policies/sca-test
    name: sca-test
    enforcement: draft
    
  # SAST - test on components with Semgrep Code
  - uses: ./policies/sast-test
    name: sast-test
    enforcement: draft
    
  # Container Scan - test on components with container scanning
  - uses: ./policies/container-scan-test
    name: container-scan-test
    enforcement: draft
    
  # IaC Scan - test on components with IaC scanning
  - uses: ./policies/iac-scan-test
    name: iac-scan-test
    enforcement: draft
```

### Test Components

| Component | Has SCA | Has SAST | Has Container | Has IaC |
|-----------|---------|----------|---------------|---------|
| `pantalasa/backend` | ✅ Snyk | ❓ | ❓ | ❓ |
| `pantalasa-cronos/kafka-go` | ❓ Semgrep | ✅ Semgrep | ❓ | ❓ |

Run dev commands:

```bash
export LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643

# Test SCA on backend (has Snyk)
lunar policy dev sca-test.executed --component github.com/pantalasa/backend
lunar policy dev sca-test.no-critical --component github.com/pantalasa/backend

# Check what data is available
lunar component get github.com/pantalasa/backend --json | jq '.sca'
lunar component get github.com/pantalasa/backend --json | jq '.sast'
lunar component get github.com/pantalasa/backend --json | jq '.container_scan'
lunar component get github.com/pantalasa/backend --json | jq '.iac_scan'
```

### Expected Results

| Check | Component with Scanner | Component without Scanner |
|-------|----------------------|---------------------------|
| `executed` | ✅ Pass | ❌ Fail (no data) |
| `no-critical` | ✅ Pass (if no criticals) or ❌ Fail | ⏭️ Skip |
| `no-high` | ✅ Pass (if no highs) or ❌ Fail | ⏭️ Skip |
| `max-total` | ✅ Pass (if under threshold) | ⏭️ Skip |

---

## PR Workflow

```bash
cd /home/brandon/code/earthly/lunar-lib-wt-security-policies

# Verify staged files
git diff --name-only main

# Run lints
earthly +lint

# Commit and push
git add .
git commit -m "Add security scanning policies (SCA, SAST, Container, IaC)

Four policies that enforce security scanning standards:
- sca: Software Composition Analysis
- sast: Static Application Security Testing  
- container-scan: Container image vulnerabilities
- iac-scan: Infrastructure as Code security

Each policy includes:
- scanned: Verify scanner ran
- no-critical: No critical findings
- no-high: No high findings (configurable)
- max-total: Total under threshold (configurable)

Works with any scanner that writes to normalized paths."

git push -u origin brandon/security-policies

# Create draft PR
gh pr create --draft \
  --title "Add security scanning policies (SCA, SAST, Container, IaC)" \
  --body "See commit message for details.

🤖 *This PR was implemented by an AI agent.*"
```

---

## Post-Merge

```bash
# Remove worktree
cd /home/brandon/code/earthly/lunar-lib
git worktree remove ../lunar-lib-wt-security-policies

# Update pantalasa-cronos to use @main
# Edit lunar-config.yml: change @brandon/security-policies to @main
```

---

## Notes

- All 4 policies are tool-agnostic — they work with any collector that writes to the normalized paths
- The `scanned` check is the only one that fails on missing data; others skip gracefully
- The `no-high` and `max-total` checks are configurable via inputs
- Consider adding a `source-tool` check if compliance requires a specific scanner
