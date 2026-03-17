# Trivy Vulnerability Scanner Collector — Implementation Plan

## Overview

A new `trivy` collector plugin for lunar-lib that scans source code dependencies for known vulnerabilities using [Trivy](https://github.com/aquasecurity/trivy). Runs as a **code collector** (no secrets, no vendor accounts) and writes normalized vulnerability data to `.sca` in the Component JSON, making it immediately consumable by the existing `sca` policy and the Image & SBOM Explorer dashboard.

---

## Architecture

```
collectors/trivy/
├── lunar-collector.yml   # Manifest: name, hooks, image, example JSON
├── README.md             # Standard collector README
├── scan.sh               # Code hook: trivy fs → .sca
├── assets/
│   └── trivy.svg         # Icon (black fill)
└── Earthfile             # Builds earthly/lunar-lib:trivy-main
```

### Sub-collector: `scan` (code hook)

- **Hook:** `code` (runs on every push to default branch and PRs)
- **What it does:**
  1. Runs `trivy fs --scanners vuln --format json --quiet .` against the repo filesystem
  2. Parses the JSON output (jq) to extract vulnerabilities
  3. Normalizes into the standard `.sca` schema
  4. Writes via `lunar collect`
- **No secrets required.** Trivy's vuln DB is bundled in the Docker image (downloaded at image build time).

### Component JSON Paths

Writes to the **existing `.sca` category** (tool-agnostic, per conventions):

| Path | Type | Description |
|------|------|-------------|
| `.sca.source.tool` | string | `"trivy"` |
| `.sca.source.version` | string | Trivy version |
| `.sca.source.integration` | string | `"code"` |
| `.sca.vulnerabilities.critical` | int | Count of critical vulns |
| `.sca.vulnerabilities.high` | int | Count of high vulns |
| `.sca.vulnerabilities.medium` | int | Count of medium vulns |
| `.sca.vulnerabilities.low` | int | Count of low vulns |
| `.sca.vulnerabilities.total` | int | Total count |
| `.sca.findings[]` | array | Individual vulnerability findings |
| `.sca.findings[].severity` | string | `"critical"`, `"high"`, `"medium"`, `"low"` |
| `.sca.findings[].package` | string | Vulnerable package name |
| `.sca.findings[].version` | string | Installed version |
| `.sca.findings[].ecosystem` | string | Package ecosystem (e.g., `"gomod"`, `"npm"`, `"pip"`) |
| `.sca.findings[].cve` | string | CVE ID (e.g., `"CVE-2023-44487"`) |
| `.sca.findings[].title` | string | Vulnerability title |
| `.sca.findings[].fix_version` | string | Version that fixes the vuln (if available) |
| `.sca.findings[].fixable` | bool | Whether a fix version exists |
| `.sca.summary.has_critical` | bool | Any critical vulns? |
| `.sca.summary.has_high` | bool | Any high vulns? |
| `.sca.summary.all_fixable` | bool | All vulns have fix versions? |

**Note on `.sca` vs `.container_scan`:** This collector writes to `.sca` because it scans source code dependencies (the filesystem), not a container image. The `.container_scan` category is reserved for image-level scanning (OS package vulns from image layers). See "Future: Container Image Scanning" below.

### Trivy JSON Output → Component JSON Mapping

Trivy's `--format json` output structure:

```json
{
  "Results": [
    {
      "Target": "go.sum",
      "Class": "lang-pkgs",
      "Type": "gomod",
      "Vulnerabilities": [
        {
          "VulnerabilityID": "CVE-2023-44487",
          "PkgName": "golang.org/x/net",
          "InstalledVersion": "0.7.0",
          "FixedVersion": "0.17.0",
          "Severity": "HIGH",
          "Title": "HTTP/2 Rapid Reset",
          "PrimaryURL": "https://avd.aquasec.com/nvd/cve-2023-44487"
        }
      ]
    }
  ]
}
```

Mapping:
- `Results[].Vulnerabilities[].Severity` → lowercase → `.sca.findings[].severity`
- `Results[].Vulnerabilities[].PkgName` → `.sca.findings[].package`
- `Results[].Vulnerabilities[].InstalledVersion` → `.sca.findings[].version`
- `Results[].Type` → `.sca.findings[].ecosystem`
- `Results[].Vulnerabilities[].VulnerabilityID` → `.sca.findings[].cve`
- `Results[].Vulnerabilities[].Title` → `.sca.findings[].title`
- `Results[].Vulnerabilities[].FixedVersion` → `.sca.findings[].fix_version`
- Presence of `FixedVersion` → `.sca.findings[].fixable`

Severity counts aggregated across all `Results[]` entries.

---

## Docker Image

`earthly/lunar-lib:trivy-main`

Based on `+base-image` (Alpine). Install Trivy binary + pre-download the vulnerability DB at build time so scans don't need network access at runtime.

```dockerfile
# Earthfile
VERSION 0.8

image:
    FROM --pass-args ../../+base-image

    ARG TRIVY_VERSION=0.58.2
    ARG TARGETARCH
    RUN curl -sSfL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TARGETARCH}.tar.gz" | tar xz -C /usr/local/bin trivy && \
        chmod +x /usr/local/bin/trivy

    # Pre-download vuln DB so scans work offline
    RUN trivy fs --download-db-only --quiet

    RUN trivy version

    ARG VERSION=main
    SAVE IMAGE --push earthly/lunar-lib:trivy-$VERSION
```

**Important:** The vuln DB is ~40MB compressed. Pre-downloading means the image is larger but scans are fast and don't need network access. The DB ages over time — the image should be rebuilt periodically (weekly via CI or on each lunar-lib merge to main).

---

## Script: `scan.sh`

```bash
#!/bin/bash
set -e

echo "Running Trivy vulnerability scan" >&2

# Record source metadata
TRIVY_VERSION=$(trivy version -f json 2>/dev/null | jq -r '.Version // empty' || echo "")
lunar collect ".sca.source.tool" "trivy"
lunar collect ".sca.source.integration" "code"
[ -n "$TRIVY_VERSION" ] && lunar collect ".sca.source.version" "$TRIVY_VERSION"

# Run Trivy filesystem scan
RESULTS_FILE="/tmp/trivy-results.json"
trivy fs --scanners vuln --format json --quiet . > "$RESULTS_FILE" 2>/dev/null || {
    echo "Trivy scan failed" >&2
    exit 1
}

# Check if any vulnerabilities found
VULN_COUNT=$(jq '[.Results[]? | .Vulnerabilities[]?] | length' "$RESULTS_FILE")
if [ "$VULN_COUNT" = "0" ] || [ -z "$VULN_COUNT" ]; then
    echo "No vulnerabilities found" >&2
    # Still write zero counts so policies can verify scan ran
    lunar collect -j ".sca.vulnerabilities" '{"critical":0,"high":0,"medium":0,"low":0,"total":0}'
    lunar collect -j ".sca.summary" '{"has_critical":false,"has_high":false,"all_fixable":true}'
    exit 0
fi

# Build normalized findings and counts using jq
jq -c '{
  vulnerabilities: {
    critical: [.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length,
    high:     [.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")]     | length,
    medium:   [.Results[]?.Vulnerabilities[]? | select(.Severity == "MEDIUM")]   | length,
    low:      [.Results[]?.Vulnerabilities[]? | select(.Severity == "LOW")]      | length,
    total:    [.Results[]?.Vulnerabilities[]?] | length
  },
  findings: [.Results[] as $r | $r.Vulnerabilities[]? | {
    severity:    (.Severity | ascii_downcase),
    package:     .PkgName,
    version:     .InstalledVersion,
    ecosystem:   $r.Type,
    cve:         .VulnerabilityID,
    title:       .Title,
    fix_version: (.FixedVersion // null),
    fixable:     (.FixedVersion != null and .FixedVersion != "")
  }],
  summary: {
    has_critical: ([.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length > 0),
    has_high:     ([.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length > 0),
    all_fixable:  ([.Results[]?.Vulnerabilities[]? | select(.FixedVersion == null or .FixedVersion == "")] | length == 0)
  }
}' "$RESULTS_FILE" | lunar collect -j ".sca" -

echo "Found $VULN_COUNT vulnerabilities" >&2
```

---

## Interaction with Existing Collectors

**Snyk collector conflict:** If both `trivy.scan` and `snyk.github-app` run for the same component, both write to `.sca`. The hub merges collection records, so the last writer wins for overlapping paths. This is acceptable — organizations will configure one or the other, not both. Document this in the README:

> **Note:** If you already use the `snyk` collector, the `trivy` collector will overwrite `.sca` data. Use one SCA scanner per component, not both.

**Syft collector synergy:** Trivy scans the filesystem independently of Syft. They complement each other — Syft generates the SBOM (`.sbom`), Trivy finds the CVEs (`.sca`). No conflict.

---

## Manifest: `lunar-collector.yml`

```yaml
version: 0

name: trivy
description: |
  Scan source code dependencies for known vulnerabilities using Trivy.
author: support@earthly.dev

default_image: earthly/lunar-lib:trivy-main

landing_page:
  display_name: "Trivy Vulnerability Scanner"
  long_description: |
    Automatically scans repository dependencies for known CVEs using Trivy.
    Supports Go, Node.js, Python, Java, Rust, and many other ecosystems.
    Writes normalized vulnerability data to .sca for use with the SCA policy.
    No secrets or vendor accounts required — fully free and open source.
  categories: ["security-and-compliance"]
  icon: "assets/trivy.svg"
  status: "beta"
  related:
    - slug: "sca"
      type: "policy"
      reason: "Enforces SCA vulnerability thresholds"

collectors:
  - name: scan
    description: |
      Scans the repository filesystem for dependency vulnerabilities.
      Writes normalized findings to .sca with severity counts, CVE IDs,
      affected packages, and fix versions.
    mainBash: scan.sh
    hook:
      type: code
    keywords: ["trivy", "vulnerability", "cve", "sca", "dependency scanning"]

example_component_json: |
  {
    "sca": {
      "source": {
        "tool": "trivy",
        "version": "0.58.2",
        "integration": "code"
      },
      "vulnerabilities": {
        "critical": 0,
        "high": 2,
        "medium": 5,
        "low": 3,
        "total": 10
      },
      "findings": [
        {
          "severity": "high",
          "package": "golang.org/x/net",
          "version": "0.7.0",
          "ecosystem": "gomod",
          "cve": "CVE-2023-44487",
          "title": "HTTP/2 Rapid Reset Attack",
          "fix_version": "0.17.0",
          "fixable": true
        }
      ],
      "summary": {
        "has_critical": false,
        "has_high": true,
        "all_fixable": true
      }
    }
  }
```

---

## Testing

### Local dev testing

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar
lunar collector dev trivy.scan --component github.com/pantalasa-cronos/backend
lunar collector dev trivy.scan --component github.com/pantalasa-cronos/frontend
```

### Expected results (pantalasa-cronos)

| Component | Language | Expected Outcome |
|-----------|----------|------------------|
| backend | Go | Vulns found (go.sum has dependencies) |
| frontend | Node.js | Vulns found (package-lock.json) |
| auth | Python | Vulns found (requirements.txt) |
| spark | Java/Python | Vulns found (many dependencies) |
| rust-service | Rust | Vulns found or clean (Cargo.lock) |
| kubeflow-manifests | K8s YAML | Clean (no language deps) — scan should complete with 0 vulns |

### Edge cases to test

1. **Repo with no language dependencies** (e.g., kubeflow-manifests) — should write zero counts, not error
2. **Large repo** (e.g., earthly-cloud with 4941 SBOM packages) — verify scan completes within timeout
3. **Multiple ecosystems in one repo** — verify all are aggregated into single `.sca` output

---

## Dashboard Integration

The Image & SBOM Explorer dashboard (`image-sbom-explorer`) already has columns for SCA vulnerability data. Once this collector runs:

- **Built Images table:** "SCA Vulns" column will show actual counts instead of "—"
- **SCA Vulnerability Summary:** Critical/High/Medium/Low stat panels will show real numbers
- **SCA & SBOM Summary table:** "Total Vulns" column will populate

No dashboard changes needed — the queries already read from `.sca.vulnerabilities`.

---

## Future: Container Image Scanning (document in PR description only)

In the future, a second sub-collector can be added to scan **built container images** for OS-level vulnerabilities (e.g., CVEs in Alpine's `openssl` or Debian's `libc`). This would write to `.container_scan` (not `.sca`).

**Proposed approach:** A code collector (not CI) that:

1. Reads `.containers.builds[].image` and `.containers.builds[].tag` from the Component JSON (written by the `docker.cicd` CI collector on a prior commit)
2. Pulls and scans the published image with `trivy image <ref> --format json`
3. Writes normalized results to `.container_scan` with image reference, OS info, and per-severity vuln counts

This avoids impacting CI (it runs as a code collector after CI completes) while still scanning the actual production image. It depends on:
- The image being pushed to an accessible registry during CI
- The collector having pull access (may need registry credentials as a secret)
- The `docker.cicd` collector having already written the image reference

**This is not part of the initial PR** — just document the vision in the PR description for reviewer context.

---

## PR Workflow

1. **Spec-first PR:** Submit `lunar-collector.yml` + `README.md` + `example_component_json` + empty `scan.sh` stub. Wait for Brandon/Vlad approval.
2. **Implementation:** After "go ahead", add `scan.sh`, `Earthfile`, SVG icon. Build and push Docker image.
3. **Test:** Run against pantalasa-cronos components, verify dashboard populates.
4. **PR description:** Include the "Future: Container Image Scanning" section as a note for reviewer context. Something like:

   > **Future enhancement (not in this PR):** A second sub-collector (`trivy.image`) can scan built container images by reading image references from `.containers.builds[]` (written by the docker CI collector). This would run as a code collector to avoid impacting CI, writing to `.container_scan` with OS-level vulnerability data. See the implementation plan for details.

---

## Installation

```yaml
# lunar-config.yml
collectors:
  - uses: github://earthly/lunar-lib/collectors/trivy@main
    on: ["domain:engineering"]
```

Zero config. Works with any language Trivy supports (Go, Node.js, Python, Java, Rust, Ruby, PHP, .NET, etc.).
