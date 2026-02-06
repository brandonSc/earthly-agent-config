# Lunar Plugin Development Guide

Complete guide for AI agents building collectors and policies in lunar-lib.

---

## 1. Before You Start

### Pull Latest Guidelines

```bash
cd ~/code/earthly/earthly-agent-config && git pull
```

### Build and Install Latest Lunar CLI

Pull and rebuild only if there are new changes:

```bash
cd /home/brandon/code/earthly/lunar
LOCAL_SHA=$(git rev-parse HEAD)
git pull origin main
if [ "$(git rev-parse HEAD)" != "$LOCAL_SHA" ]; then
  earthly +build-cli
  sudo cp dist/lunar-linux-amd64 /usr/local/bin/lunar
fi
```

### Update lunar-lib

```bash
cd /home/brandon/code/earthly/lunar-lib
git checkout main && git pull origin main
```

### Read the Documentation

Before implementing, read these docs in `lunar-lib/ai-context/`:

| Document | Purpose |
|----------|---------|
| `about-lunar.md` | High-level overview of Lunar |
| `core-concepts.md` | Architecture and key entities |
| `collector-reference.md` | How to write collectors |
| `policy-reference.md` | How to write policies |
| `component-json/conventions.md` | Schema design principles |
| `component-json/structure.md` | Component JSON paths |

Also read the Lunar docs at https://docs-lunar.earthly.dev

### Keep This Guide Updated (Self-Improvement)

When you learn something the hard way — through mistakes you fixed automatically or corrections from the user — **update this guide and AGENTS.md** so future agents don't repeat the same errors.

**What to document:**
- Commands that failed and the fix you discovered
- Missing steps or prerequisites
- Workarounds for unexpected issues
- Better approaches than what was documented
- Common CI failures and their solutions

**What NOT to document:**
- Task-specific details (specific policy names, one-off fixes)
- Things only relevant to the current implementation
- Obvious or trivial issues

**After updating, commit and push:**
```bash
cd ~/code/earthly/earthly-agent-config
git add . && git commit -m "Guide: <what you learned>" && git push
```

This is critical for continuous improvement — each agent should leave the docs better than they found them.

### Editing `ai-context/` Documentation

When making changes to files in `lunar-lib/ai-context/`, keep content **concise and declarative**:

- **Don't include verbose code examples** — The ai-context docs define conventions and rules, not tutorials. Reference existing implementations (e.g., "See `collectors/golang/cicd.sh`") instead of inlining full bash scripts or large JSON blocks.
- **Prefer tables and short rules** over lengthy prose with examples.
- **Minimal JSON snippets are OK** for schema definitions in `component-json/`, but keep them short (3-5 lines showing structure, not full realistic payloads).

---

## 2. Git Worktrees

Use git worktrees for parallel development. Each worktree is a separate directory on its own branch.

### Create a Worktree

```bash
cd /home/brandon/code/earthly/lunar-lib
git worktree add ../lunar-lib-wt-<feature-name> -b brandon/<feature-name>
```

### List Worktrees

```bash
git worktree list
```

### Remove After Merge

```bash
git worktree remove ../lunar-lib-wt-<feature-name>
```

### Naming Convention

- Worktree directory: `lunar-lib-wt-<feature-name>`
- Branch name: `brandon/<feature-name>`

---

## 3. Implementing Collectors

### Directory Structure

```
lunar-lib/collectors/<collector-name>/
├── lunar-collector.yml    # Manifest (required)
├── main.sh                # Main script
├── helpers.sh             # Shared functions (optional)
├── README.md              # Documentation
└── assets/
    └── <collector>.svg    # Icon for landing page
```

### lunar-collector.yml Format

```yaml
version: 0

name: my-collector
description: What this collector does
author: support@earthly.dev

default_image: earthly/lunar-lib:base-main
default_image_ci_collectors: native  # Only if you have CI hooks

landing_page:
  display_name: "My Collector"  # Max 50 chars
  long_description: |
    Multi-line description for the landing page.
    Explain what data is collected and why.
  category: "devex-build-and-ci"  # See categories below
  icon: "assets/my-collector.svg"
  status: "stable"  # stable|beta|experimental|deprecated
  related:
    - slug: "my-policy"
      type: "policy"
      reason: "Enforces standards using this collector's data"

collectors:
  - name: main
    description: |
      Detailed description of what this sub-collector does.
      Shown on landing page.
    mainBash: main.sh
    hook:
      type: code  # code|cron|ci-before-job|ci-after-job|ci-before-step|ci-after-step|ci-before-command|ci-after-command
    keywords: ["keyword1", "keyword2", "seo term"]

inputs:
  my_input:
    description: Description of the input
    default: "default-value"

secrets:
  - name: API_TOKEN
    description: API authentication token
    required: true

example_component_json: |
  {
    "category": {
      "field": "value"
    }
  }
```

Don't over-document implementation details. Only document what is needed to understand the collector. More details can be added to READMEs for the collector or policy.

### Docker Image Rules

**This is a common source of mistakes.** Follow these rules exactly:

| Scenario | `default_image` value |
|----------|----------------------|
| No extra dependencies needed | `earthly/lunar-lib:base-main` |
| Extra dependencies needed (e.g., Go, Python) | `earthly/lunar-lib:<collector-name>-main` (requires custom Earthfile) |
| CI hooks only (runs on user's runner) | `native` or omit (with `default_image_ci_collectors: native`) |

**Do NOT use `earthly/lunar-scripts:1.0.0`** — that is a legacy image. Always use `earthly/lunar-lib:base-main` or a custom image built from it.

**For development/testing on a branch:** Build and push with a temporary tag:

```bash
# If using base image (no extra deps), no build needed — just use base-main
# If using custom image:
cd /home/brandon/code/earthly/lunar-lib-wt-<feature>/collectors/<name>
earthly --push +image --VERSION=brandon-<feature>
# Pushes: earthly/lunar-lib:<name>-brandon-<feature>
```

Then temporarily set that tag in `lunar-collector.yml` for testing. **Before committing, revert to `-main`:**

```yaml
default_image: earthly/lunar-lib:<name>-main  # Always -main in committed code
```

### Categories

- `devex-build-and-ci` — Build systems, CI/CD, developer experience
- `security-and-compliance` — Security scanning, compliance
- `testing-and-quality` — Testing, coverage, quality metrics
- `deployment-and-infrastructure` — K8s, containers, IaC
- `repository-and-ownership` — README, CODEOWNERS, repo structure
- `operational-readiness` — On-call, runbooks, observability

### Hook Types

| Hook | When It Runs | Use Case |
|------|--------------|----------|
| `code` | On code push | Analyze source files |
| `cron` | On schedule | Query external APIs |
| `ci-before-job` | Before CI job | Start tracing span |
| `ci-after-job` | After CI job | End tracing span |
| `ci-before-step` | Before CI step | Capture step start |
| `ci-after-step` | After CI step | Capture step end |
| `ci-before-command` | Before command | Record command start |
| `ci-after-command` | After command | Capture command output |

### Execution Environment Differences

**Important:** The environment where your collector runs depends on the hook type, but only if there's an install.sh and if there is no default image set in the lunar-collector.yml file or the default image is set to `native`.

| Hook Type | Runs In | Implications for `install.sh` |
|-----------|---------|-------------------------------|
| `code`, `cron` | Lunar's container (Debian-based) | Can assume `apt-get`, predictable environment |
| `ci-*` hooks | User's CI runner (varies) | Must support multiple package managers (apk/apt-get/yum) |

For CI collectors with `default_image_ci_collectors: native`, the scripts run directly on the user's CI runner. This could be Ubuntu, Alpine, RHEL, or any Linux distro. Your `install.sh` must detect the available package manager.

For code collectors, scripts run in the `earthly/lunar-lib:base-main` container (Alpine-based). You can use `apk add` for installing packages.

### Separating PR vs Main Branch Logic

Use `runs_on` to cleanly separate collectors instead of if/else blocks:

```yaml
collectors:
  - name: github-app-pr
    mainBash: github-app.sh
    hook:
      type: code
      runs_on: [prs]  # Only runs on PRs
    
  - name: github-app-main
    mainBash: github-app-main.sh
    hook:
      type: code
      runs_on: [default-branch]  # Only runs on main/master
```

### Writing to Component JSON

```bash
# Simple value
lunar collect -j ".category.field" "value"

# JSON object
jq -n '{field: "value"}' | lunar collect -j ".category" -

# Multiple values
lunar collect -j ".cat.field1" "val1" ".cat.field2" "val2"
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `LUNAR_COMPONENT_ID` | e.g., `github.com/org/repo` |
| `LUNAR_COMPONENT_PR` | PR number (empty on main branch) |
| `LUNAR_COMPONENT_GIT_SHA` | Full commit SHA |
| `LUNAR_PLUGIN_ROOT` | Path to collector directory |
| `LUNAR_VAR_<name>` | Input values |
| `LUNAR_SECRET_<name>` | Secret values |

---

## 4. Implementing Policies

### Policy Grouping Principle

**Policies that operate on the same root Component JSON field should be grouped as checks within a single policy plugin.**

For example, all checks that read from `.testing.*` should be in one `testing` policy:
- `executed` → reads `.testing`
- `passing` → reads `.testing.all_passing`
- `coverage-collected` → reads `.testing.coverage`
- `coverage-reported` → reads `.testing.coverage.percentage`
- `min-coverage` → reads `.testing.coverage.percentage`

**Why?** This creates logical groupings, simplifies configuration, and allows users to `include` specific checks from a single policy rather than managing multiple separate policies.

**Anti-pattern:** Don't create separate `testing`, `coverage`, `test-results` policies if they all read `.testing.*` data.

### Consolidating Existing Policies

When merging an existing policy into another (e.g., moving `coverage` checks into `testing`):

1. **Copy all check files** from the old policy to the new one
2. **Add policy definitions** to the new `lunar-policy.yml`
3. **Update collector `related` references** — Any collectors that had `related: coverage` must be updated to `related: testing`
4. **Port README content** — Move useful examples and explanations to the new README
5. **Delete the old policy directory** completely
6. **Test with `lunar policy dev`** for each migrated check

**Common mistake:** Forgetting to update collector `lunar-collector.yml` files that referenced the deleted policy in their `related` field. This will cause CI lint failures.

### Directory Structure

```
lunar-lib/policies/<policy-name>/
├── lunar-policy.yml       # Manifest (required)
├── check-name.py          # One file per check
├── another-check.py
├── requirements.txt       # lunar-policy==0.2.2
├── test_policy.py         # Unit tests (optional but recommended)
├── README.md
└── assets/
    └── <policy>.svg
```

### lunar-policy.yml Format

```yaml
version: 0

name: my-policy
description: What this policy enforces
author: support@earthly.dev

default_image: earthly/lunar-lib:base-main

landing_page:
  display_name: "My Policy"
  long_description: |
    Multi-line description explaining what standards
    this policy enforces and why.
  category: "testing-and-quality"
  icon: "assets/my-policy.svg"
  status: "stable"
  requires:
    - slug: "my-collector"
      type: "collector"
      reason: "Provides data for this policy"
  related: []

policies:
  - name: check-name
    description: |
      Detailed description of what this check validates.
    mainPython: ./check-name.py
    keywords: ["keyword1", "keyword2"]

inputs:
  threshold:
    description: Threshold value for the check
    default: "10"
```

### The Node Pattern (Preferred)

Use this pattern for clean, readable policy code:

```python
from lunar_policy import Check

def check_example(node=None):
    c = Check("example-check", "Description here", node=node)
    with c:
        # 1. Get the parent node first
        go = c.get_node(".lang.go")
        if not go.exists():
            c.skip("Not a Go project")

        # 2. Navigate from that node for nested paths
        version_node = go.get_node(".version")
        if not version_node.exists():
            c.skip("Version data not available")

        # 3. Get value only after confirming existence
        version = version_node.get_value()

        # 4. Make assertions
        c.assert_true(version >= "1.21", f"Version {version} too old")
    return c

if __name__ == "__main__":
    check_example()
```

### Key Points

- Use `c.get_node(".path")` then `node.exists()` to check data availability
- Never call `get_value()` without first checking `exists()`
- **`c.skip()` raises `SkippedError`** — no `return` needed after it
- **There is no `c.succeed()` method** — checks auto-pass if no assertions fail

### When to Skip vs Fail (Score Impact)

**This is critical for accurate compliance scores.**

**✅ GOOD place to skip:** When the policy doesn't apply to the component
```python
# Skip if not a language project (docs-only repos, infrastructure, etc.)
if not c.get_node(".lang").exists():
    c.skip("No language project detected")
```

**❌ BAD place to skip:** When data is missing that the policy expects
```python
# DON'T skip when coverage is missing - FAIL instead
# This ensures the score reflects missing coverage
if not c.get_node(".testing.coverage").exists():
    c.skip("No coverage data")  # ❌ Wrong - hides the problem

# DO use assert_exists - score correctly reflects failure
c.assert_exists(".testing.coverage", "No coverage data collected")  # ✅ Correct
```

**Why this matters:**
- **Skipped checks don't affect the compliance score** — the problem is hidden
- **Failed checks lower the score** — accurately reflects missing data
- If a component IS a valid language project but lacks test/coverage data, all related checks should FAIL
- This gives users accurate feedback: "You have 5 failing checks related to testing"

### Data Existence Checks (Common Bug Source)

There are **three different patterns** for checking if data exists. Using the wrong one causes bugs:

#### Pattern 1: `assert_exists()` — For Required Data (Pass/Fail)

Use when missing data should **fail or pend** the check:

```python
# If .testing doesn't exist, check becomes PENDING (waiting for collectors)
# or FAIL (if collectors finished and data is still missing)
c.assert_exists(".testing", "No test execution data found")
```

#### Pattern 2: `get_node().exists()` — For Conditional Logic (Skip)

Use when you need a **boolean** to decide whether to skip:

```python
# Returns True/False without raising exceptions
if not c.get_node(".lang").exists():
    c.skip("No language project detected")  # raises SkippedError, exits with block
```

#### ❌ WRONG: Using `c.exists()` for Skip Logic

```python
# BAD - c.exists() raises NoDataError, so skip() is never reached!
if not c.exists(".testing"):
    c.skip("...")  # Unreachable!
```

#### Summary Table

| Method | Returns | Use For |
|--------|---------|---------|
| `c.assert_exists(path, msg)` | Nothing (raises on missing) | Required data - fail if missing |
| `c.get_node(path).exists()` | `True`/`False` | Conditional logic - skip if missing |
| `c.exists(path)` | Raises `NoDataError` if missing | **Avoid** - confusing behavior |

**Good example:** See `lunar-lib/policies/testing/executed.py` — uses `get_node().exists()` for language detection (valid skip), then `assert_exists()` for required data (fail if missing).

### Available Assertions

```python
c.assert_exists(".path", "Error message")
c.assert_true(condition, "Error message")
c.assert_false(condition, "Error message")
c.assert_equal(actual, expected, "Error message")
c.assert_less_or_equal(value, max_val, "Error message")
c.assert_greater_or_equal(value, min_val, "Error message")
```

### Getting Values

```python
# Check existence first
if c.exists(".path"):
    value = c.get_value(".path")

# Or with default
value = c.get_value_or_default(".path", "default")

# Using nodes
node = c.get_node(".path")
if node.exists():
    value = node.get_value()
```

### Reading Inputs

```python
from lunar_policy import variable_or_default

threshold = variable_or_default("threshold", "10")
threshold_int = int(threshold)  # Inputs are always strings
```

**⚠️ Input names must match exactly.** The name in `variable_or_default("threshold", ...)` must match exactly what's defined in `lunar-policy.yml` under `inputs:`. If your YAML has `min_go_version` but you call `variable_or_default("min_version", ...)`, the policy will use the default value silently. Similarly, when configuring in `lunar-config.yml`, the `with:` keys must match the YAML input names exactly.

### Unit Tests

Create `test_<policy>.py`:

```python
import pytest
from lunar_policy.testing import PolicyTestCase

class TestMyCheck(PolicyTestCase):
    policy_path = "policies/my-policy"
    policy_name = "check-name"
    
    def test_pass_when_data_exists(self):
        self.set_component_json({
            "category": {"field": "good-value"}
        })
        self.assert_pass()
    
    def test_fail_when_data_bad(self):
        self.set_component_json({
            "category": {"field": "bad-value"}
        })
        self.assert_fail()
    
    def test_skip_when_no_data(self):
        self.set_component_json({})
        self.assert_skip()
```

Run tests:

```bash
python -m pytest policies/<name>/test_*.py -v
```

### requirements.txt

```
lunar-policy==0.2.2
```

### SDK Reference

https://docs-lunar.earthly.dev/plugin-sdks/python-sdk/policy

### Policy Style Guidelines

**Naming:** README title AND `display_name` must end with **"Guardrails"** (e.g., "Testing Guardrails"), not "Policies".

**Descriptions in lunar-policy.yml should be user-focused:**
- ❌ BAD: "Skips if pass/fail data is not available (some collectors only report execution, not results)"
- ✅ GOOD: "Ensures all tests pass. Skips if project does not contain a specified language."

Move implementation details (data paths, skip conditions, collector specifics) to README only.

**Consistency across related checks:** When you have multiple checks that do similar things (e.g., `min-go-version` and `min-go-version-cicd` both parsing versions), keep the implementation logic consistent. Code reviewers will flag inconsistencies, and bugs are more likely when similar code behaves differently.

### Debugging Tips

- **Branch refs may cache** — If `@brandon/branch` shows stale behavior, copy to `./policies/<name>-test/` instead
- **Debug prints** — Add to the test copy, not the source
- **Docker required** — `lunar policy dev` needs Docker Desktop running

---

## 5. Creating Plugin Icons

Every collector and policy needs an SVG icon for the landing page. The icon goes in `assets/<plugin-name>.svg`.

### Design Guidelines

| Scenario | Approach |
|----------|----------|
| **Technology-specific** (e.g., Go, Python, Snyk) | Use the official technology logo or something inspired by it |
| **Generic plugin** (e.g., testing, coverage) | Generate an icon that visually represents the concept |

### Technical Requirements

**Critical: Use transparency, not solid backgrounds**

The website displays icons on dark backgrounds. If your SVG has a solid background color, it will appear as a flat rectangle:

```svg
<!-- ❌ BAD: Solid background gets flattened -->
<svg viewBox="0 0 64 64">
  <rect width="64" height="64" fill="#1a1a1a"/>
  <path d="..." fill="white"/>
</svg>

<!-- ✅ GOOD: Transparent background -->
<svg viewBox="0 0 64 64">
  <path d="..." fill="white"/>
</svg>
```

**Critical: Ensure contrast for embedded elements**

If your icon has nested elements (e.g., a small symbol inside a larger shape), ensure there's enough contrast between them. Light-on-light elements become invisible:

```svg
<!-- ❌ BAD: White inner icon on light gray shape = invisible -->
<svg viewBox="0 0 64 64">
  <rect x="8" y="8" width="48" height="56" rx="4" fill="#e0e0e0"/>
  <path d="..." fill="white"/>  <!-- Can't see this! -->
</svg>

<!-- ✅ GOOD: Dark inner icon on light shape = visible -->
<svg viewBox="0 0 64 64">
  <rect x="8" y="8" width="48" height="56" rx="4" fill="#e0e0e0"/>
  <path d="..." fill="#333333"/>  <!-- Visible contrast -->
</svg>

<!-- ✅ ALSO GOOD: Use transparency/cutouts instead of layered fills -->
<svg viewBox="0 0 64 64">
  <path d="M8,8 h48 v56 h-48 z M16,20 ..." fill="white" fill-rule="evenodd"/>
</svg>
```

### SVG Specifications

- **Size**: 64x64 viewBox recommended
- **Colors**: Use white (`#ffffff`) or light colors for outer shapes on dark backgrounds
- **Embedded elements**: Use dark colors (`#333333`) or cutouts for inner icons/symbols
- **Background**: Transparent (no `<rect>` filling the viewBox)
- **Format**: Clean, minified SVG without embedded fonts or images

### Generating Icons

For technology logos:
1. Find the official SVG logo (check the project's brand assets, GitHub, or CNCF artwork repo)
2. Simplify if needed (remove backgrounds, reduce complexity)
3. Ensure transparent background

```bash
# CNCF projects have official logos at:
curl -sL "https://raw.githubusercontent.com/cncf/artwork/master/projects/<project>/icon/color/<project>-icon-color.svg"
```

For custom icons:
1. Use an AI image generator or icon tool to create a concept
2. Convert to clean SVG (tools like Figma, Inkscape, or online converters)
3. Manually clean up: remove backgrounds, ensure transparency
4. Test on dark background before committing

### Adding Overlays (Badges, Text)

When adding text badges or overlays to existing logos:

**Use SVG masks for transparent cutouts** (not white text):
```svg
<!-- ✅ GOOD: Letters cut out, showing through to background -->
<svg viewBox="0 0 100 100">
  <defs>
    <mask id="badge-cutout">
      <circle cx="15" cy="15" r="12" fill="white"/>
      <text x="15" y="20" font-size="12" fill="black">CI</text>
    </mask>
  </defs>
  <circle cx="15" cy="15" r="12" fill="#425cc7" mask="url(#badge-cutout)"/>
</svg>

<!-- ❌ BAD: White text won't work on light backgrounds -->
<circle cx="15" cy="15" r="12" fill="#425cc7"/>
<text x="15" y="20" fill="white">CI</text>
```

### Transforms and Centering

When scaling/translating external logos, be careful not to push elements outside the viewBox:

```svg
<!-- ❌ BAD: Logo pushed below viewBox boundary (cropped) -->
<g transform="translate(5, 20) scale(0.09)">
  <!-- 1000px logo * 0.09 = 90px, starting at y=20 = ends at y=110, but viewBox is 100 -->
</g>

<!-- ✅ GOOD: Center first, then scale, then offset to center -->
<g transform="translate(50, 50) scale(0.085) translate(-500, -500)">
  <!-- Move to center, scale down, then offset by half the original size -->
</g>
```

### Testing Your Icon

Before committing, test that your icon renders correctly:

```bash
# Quick visual test - open in browser on dark background
echo '<html><body style="background:#1e1e1e;padding:20px">
<img src="assets/my-plugin.svg" width="64" height="64">
</body></html>' > /tmp/icon-test.html
# Open /tmp/icon-test.html in browser
```

---

## 6. Testing in pantalasa-cronos

Use `pantalasa-cronos` for integration testing (not `pantalasa` which may have demos running).

### Environment Setup

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar
export LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643
# Hub: cronos.demo.earthly.dev
```

### Available Test Components

| Component | Language | Tags | Cloned At |
|-----------|----------|------|-----------|
| `github.com/pantalasa-cronos/backend` | Go | go, SOC2 | `pantalasa-cronos/backend` |
| `github.com/pantalasa-cronos/frontend` | Node.js | node | `pantalasa-cronos/frontend` |
| `github.com/pantalasa-cronos/auth` | Python | python, SOC2 | `pantalasa-cronos/auth` |
| `github.com/pantalasa-cronos/kafka-go` | Go | go, kafka | `pantalasa-cronos/kafka-go` |
| `github.com/pantalasa-cronos/hadoop` | Java | java, SOC2 | `pantalasa-cronos/hadoop` |
| `github.com/pantalasa-cronos/spark` | Java | java, SOC2 | `pantalasa-cronos/spark` |

**Important:** All component repos are cloned in `pantalasa-cronos/`. Keep them up to date:

```bash
cd /home/brandon/code/earthly/pantalasa-cronos
for dir in backend frontend auth kafka-go hadoop spark; do
  (cd "$dir" && git pull) 2>/dev/null || true
done
```

---

### Building Custom Docker Images for Collectors

If your collector needs dependencies not in the base image, you need to build a custom image.

#### What's Already in the Base Image

The base image (`earthly/lunar-scripts`) includes these tools — **do NOT reinstall them**:

| Tool | Alpine | Debian | Notes |
|------|--------|--------|-------|
| `bash` | ✓ | ✓ | |
| `python3` | ✓ | ✓ | With venv at `/opt/venv` |
| `pip` | ✓ | ✓ | `lunar-policy` pre-installed |
| `jq` | ✓ | ✓ | JSON processing |
| `yq` | ✓ | ✓ | YAML processing |
| `curl` | ✓ | ✓ | |
| `wget` | ✓ | ✓ | |
| `parallel` | ✓ | ✓ | GNU parallel |
| `lunar` CLI | ✓ | ✓ | `/usr/bin/lunar` |

**Base image definition:** `/home/brandon/code/earthly/lunar/Earthfile` → `+lunar-scripts` target (lines ~388-423)

#### When You Need a Custom Image

- Collector requires language runtimes (Go, Node.js, Ruby, etc.)
- Collector requires specific CLI tools (golangci-lint, ast-grep, etc.)
- Collector requires system packages not listed above

#### Step 1: Create an Earthfile

Create `Earthfile` in your collector directory:

```earthfile
VERSION 0.8

image:
    # Extend from base image (Alpine-based)
    FROM --pass-args ../../+base-image
    
    # Or for Debian-based (needed for some binaries):
    # ARG SCRIPTS_VERSION=main-debian
    # FROM earthly/lunar-scripts:$SCRIPTS_VERSION
    
    # Install your dependencies
    RUN apk add --no-cache python3 py3-pip
    # Or for Debian: RUN apt-get update && apt-get install -y python3
    
    # Example: Install Go
    ARG GO_VERSION=1.23.4
    ARG TARGETARCH
    RUN wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" && \
        tar -C /usr/local -xzf "go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" && \
        rm "go${GO_VERSION}.linux-${TARGETARCH}.tar.gz"
    ENV PATH="/usr/local/go/bin:$PATH"
    
    # Verify installation
    RUN go version
    
    ARG VERSION=main
    SAVE IMAGE --push earthly/lunar-lib:<collector-name>-$VERSION
```

**Reference examples:**
- `lunar-lib/collectors/golang/Earthfile` — Go + golangci-lint
- `lunar-lib/collectors/ast-grep/Earthfile` — ast-grep CLI
- `lunar-lib/collectors/dockerfile/Earthfile` — Dockerfile tools

#### Step 2: Build and Push with Temporary Tag

For testing, use a **temporary tag** — NOT the production tag:

```bash
cd /home/brandon/code/earthly/lunar-lib-wt-<feature>/collectors/<name>

# Build with temporary test tag
earthly --push +image --VERSION=test-brandon

# This pushes: earthly/lunar-lib:<collector-name>-test-brandon
```

#### Step 3: Update lunar-collector.yml for Testing

**Only in your test copy** (pantalasa-cronos), update the image:

```yaml
# In pantalasa-cronos/lunar/collectors/<name>-test/lunar-collector.yml
version: 0
name: my-collector
default_image: earthly/lunar-lib:<collector-name>-test-brandon  # Temporary tag!
# ...
```

#### Step 4: Test in pantalasa-cronos

Run your tests using the temporary image.

#### Step 5: Before Committing to lunar-lib — CRITICAL

**Revert the image tag** in `lunar-collector.yml` before committing. Use the `-main` tag — this is the tag the release workflow produces when the PR merges:

```yaml
# In lunar-lib worktree (NOT pantalasa-cronos)
version: 0
name: my-collector
default_image: earthly/lunar-lib:<collector-name>-main  # Release tag
```

The CI will build and push `earthly/lunar-lib:<collector-name>-main` when the PR merges.

#### Step 6: Add to Root Earthfile

For the CI to build your image, add it to `lunar-lib/Earthfile`:

```earthfile
all:
    BUILD --pass-args +base-image
    BUILD --pass-args ./collectors/dockerfile+image
    BUILD --pass-args ./collectors/golang+image
    BUILD --pass-args ./collectors/ast-grep+image
    BUILD --pass-args ./collectors/<your-collector>+image  # Add this line
```

---

### Testing Collectors

**Quick dev testing (no copy needed):** For `lunar collector dev` commands, you can use relative paths directly in `lunar-config.yml`:

```yaml
collectors:
  - uses: ../lunar-lib-wt-<feature>/collectors/<name>
    on: ["domain:engineering"]
```

This is the fastest way to iterate locally. Only copy files when you need to push to a demo environment.

#### Step 1: Copy Files to Test Directory (for demo environments only)

```bash
# Copy collector to pantalasa-cronos
cp -r /home/brandon/code/earthly/lunar-lib-wt-<feature>/collectors/<name>/* \
  /home/brandon/code/earthly/pantalasa-cronos/lunar/collectors/<name>-test/
```

#### Step 2: Wire Up in lunar-config.yml

Edit `/home/brandon/code/earthly/pantalasa-cronos/lunar/lunar-config.yml`:

```yaml
collectors:
  # Add your test collector
  - uses: ./collectors/<name>-test
    on: ["domain:engineering"]  # Or specific component tags
  
  # IMPORTANT: If porting an existing collector, disable the old one:
  # - uses: github://earthly/lunar-lib/collectors/<old-name>@main
  #   on: ["domain:engineering"]
```

#### Step 3: Commit and Push

```bash
cd /home/brandon/code/earthly/pantalasa-cronos
git add lunar/collectors/<name>-test lunar/lunar-config.yml
git commit -m "Add <name> collector for testing"
git push
```

#### Step 4: Wait for GitHub Actions

Check that the pantalasa-cronos CI passes:

```bash
gh run list --repo pantalasa-cronos/lunar --limit 5
# Wait for the run to complete successfully
```

#### Step 5: Wait for Collection (5 minutes)

After CI passes, wait ~5 minutes for Lunar to run collectors on all components.

#### Step 6: Verify Component JSON

For **each relevant component**, fetch and verify the collected data:

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar

# Get Component JSON for a specific component
LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
  lunar component get github.com/pantalasa-cronos/backend --json | jq '.path.to.expected.data'

# Or get specific paths
LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
  lunar component get github.com/pantalasa-cronos/backend --json | jq '.sca'
```

**Verify for each component in lunar-config.yml that matches the collector's `on` selector.**

#### Step 7: Analyze Component Repos if Needed

If you need to understand what data should be collected, examine the component source:

```bash
# Check if component has relevant files
ls /home/brandon/code/earthly/pantalasa-cronos/backend/
cat /home/brandon/code/earthly/pantalasa-cronos/backend/go.mod
```

#### If No Relevant Test Components Exist

If none of the pantalasa-cronos components have the data your collector needs:

1. **Stop and discuss with the user** — Explain what's missing
2. **Plan a test scenario together** — Options include:
   - Adding test files to a component repo
   - Creating a new test component
   - Using a different approach

---

### Testing CI/CD Collectors

CI/CD collectors (hooks like `ci-after-job`, `ci-after-command`) require triggering actual CI builds.

#### Step 1: Trigger CI Builds

Push empty commits to trigger CI in the component repos:

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/backend
git commit --allow-empty -m "Trigger CI for collector testing"
git push

# Repeat for other relevant components
```

#### Step 2: Wait for CI to Complete

```bash
# Check GitHub Actions status
gh run list --repo pantalasa-cronos/backend --limit 3
gh run watch --repo pantalasa-cronos/backend  # Watch latest run
```

#### Step 3: Wait Additional Time

After CI completes, wait ~5 minutes for Lunar to process the CI data.

#### Step 4: Verify CI Data in Component JSON

```bash
LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
  lunar component get github.com/pantalasa-cronos/backend --json | jq '.ci'
```

---

### Testing Policies

**Quick dev testing (no copy needed):** For `lunar policy dev` commands, you can use relative paths directly in `lunar-config.yml`:

```yaml
policies:
  - uses: ../lunar-lib-wt-<feature>/policies/<name>
    name: <name>
    on: ["domain:engineering"]
    enforcement: draft
```

This is the fastest way to iterate locally. Only copy files when you need to push to a demo environment.

#### Step 1: Copy Files to Test Directory (for demo environments only)

```bash
cp -r /home/brandon/code/earthly/lunar-lib-wt-<feature>/policies/<name>/* \
  /home/brandon/code/earthly/pantalasa-cronos/lunar/policies/<name>-test/
```

#### Step 2: Wire Up in lunar-config.yml

```yaml
policies:
  # Add your test policy
  - uses: ./policies/<name>-test
    name: <name>-test
    on: ["domain:engineering"]  # Or specific tags
    enforcement: draft  # Use draft for testing
    with:
      # Policy inputs here
  
  # IMPORTANT: If porting an existing policy, disable the old one:
  # - uses: github://earthly/lunar-lib/policies/<old-name>@main
  #   ...
```

#### Step 3: Commit and Push

```bash
cd /home/brandon/code/earthly/pantalasa-cronos
git add lunar/policies/<name>-test lunar/lunar-config.yml
git commit -m "Add <name> policy for testing"
git push
```

#### Step 4: Wait for GitHub Actions

```bash
gh run list --repo pantalasa-cronos/lunar --limit 5
```

#### Step 5: Wait for Policy Evaluation (~5 minutes)

After push, Lunar will evaluate policies on all matching components.

#### Step 6: Run Policy Dev on Each Component

Test the policy against each relevant component:

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar

# Test against each component
for component in \
  github.com/pantalasa-cronos/backend \
  github.com/pantalasa-cronos/frontend \
  github.com/pantalasa-cronos/auth; do
  
  echo "=== Testing on $component ==="
  LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
    lunar policy dev <name>-test.<check> --component "$component"
done
```

#### Step 7: Verify Results Match Expectations

For each component:
1. **Check the policy result** (pass/fail/skip)
2. **Examine the component repo** to understand why
3. **Ensure the result makes sense** given the component's actual state

```bash
# Example: Check if go.mod exists before testing go-mod-exists policy
ls /home/brandon/code/earthly/pantalasa-cronos/backend/go.mod
```

#### Step 8: Test Non-Matching Components Too

**Critical:** Don't just test components where the policy should pass/fail. Also test components where the policy should **skip**:

```bash
# For a Go policy, test against a non-Go component
LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
  lunar policy dev golang.go-mod-exists --component github.com/pantalasa-cronos/frontend
# Should skip with "Not a Go project"
```

This catches bugs where `get_value()` is called on paths that don't exist when the collector hasn't run for that component.

#### If No Relevant Test Components Exist

If none of the components have the data your policy needs:

1. **Stop and discuss with the user**
2. **Plan together:**
   - Can we add test data to an existing component?
   - Should we create a dedicated test component?
   - Is there another way to validate the policy?

---

### Unit Tests (Optional, For Agent Confidence Only)

Unit tests are **optional** — the primary verification method is running `lunar collector dev` / `lunar policy dev` against real components and pushing to a test environment. If you find unit tests helpful for debugging complex logic, you can write them locally, but **do NOT commit them to lunar-lib**.

#### Create Temporary Test File

```python
# test_<policy>.py (in your worktree, don't commit)
import pytest
from lunar_policy.testing import PolicyTestCase

class TestMyCheck(PolicyTestCase):
    policy_path = "policies/<name>"
    policy_name = "<check>"
    
    def test_pass_case(self):
        self.set_component_json({"expected": "data"})
        self.assert_pass()
    
    def test_fail_case(self):
        self.set_component_json({"bad": "data"})
        self.assert_fail()
    
    def test_skip_when_no_data(self):
        self.set_component_json({})
        self.assert_skip()
```

#### Run Tests Locally

```bash
cd /home/brandon/code/earthly/lunar-lib-wt-<feature>
python -m pytest policies/<name>/test_*.py -v

# Delete test file before committing
rm policies/<name>/test_*.py
```

---

### Dev Command Quick Reference

```bash
# Policy dev (immediate, against live Component JSON)
lunar policy dev <plugin>.<check> --component github.com/pantalasa-cronos/backend

# Collector dev (runs collector locally, shows output)
lunar collector dev <plugin>.<sub> --component github.com/pantalasa-cronos/backend

# Get Component JSON
lunar component get github.com/pantalasa-cronos/backend --json

# Useful flags
--verbose          # Detailed output
--secrets "K=V"    # Pass secrets
--use-system-runtime  # Run without Docker
```

---

### Testing in Real PRs (Production Verification)

To verify collectors and policies work correctly in production, create test PRs on pantalasa components and check the **Earthly Lunar** GitHub comment.

#### Creating Test PRs

```bash
# Pick a component (backend has Snyk, whoami doesn't)
cd /home/brandon/code/earthly/pantalasa/<component>

# Create test branch
git checkout main && git pull
git checkout -b test/<description>

# Make a trivial change
echo "" >> README.md
git add README.md && git commit -m "Test: <what you're testing>"

# Push and create PR
git push -u origin test/<description>
gh pr create --title "Test: <description>" --body "Testing <what>"
```

#### Checking Lunar Results

Lunar posts a comment on each PR with policy results. To view it:

```bash
# Get the latest Lunar comment
gh api repos/pantalasa/<component>/issues/<pr-number>/comments --jq '.[-1].body'
```

#### Understanding the Lunar Comment Format

```markdown
## 🌒 Earthly Lunar

### ❌ N Failing
* ❌ **check-name** policy.check - Description
  * Error message explaining why it failed

### 🟡 N Pending  
* 🟡 **check-name** - Waiting for collector data

### ✅ N Passing
* ✅ **check-name** policy.check - Description (🔀 **required**)
```

- **❌ Failing** — Policy ran and found issues
- **🟡 Pending** — Collectors/policies still processing (wait for CI to complete)
- **✅ Passing** — Policy ran and passed
- **(🔀 required)** — Blocking checks that must pass before merge

**Important:** Always wait for pending to resolve before concluding tests. Pending means processing is incomplete, not that data is missing.

#### Test Components for Real PR Testing

| Component | Has Snyk | Good For Testing |
|-----------|----------|------------------|
| `pantalasa/backend` | ✅ Yes | SCA policies passing, Go policies |
| `pantalasa/whoami` | ❌ No | SCA policies failing (no scanner configured) |
| `pantalasa/frontend` | ✅ Yes | Node.js policies |
| `pantalasa/auth` | ✅ Yes | Python policies |

#### Cleanup Test PRs

```bash
# Close test PR
gh pr close <pr-number>

# Delete test branch
git checkout main
git branch -D test/<description>
git push origin --delete test/<description>
```

---

### Cleanup After Testing

After testing is complete and before creating PR:

```bash
# Remove test directories from pantalasa-cronos
rm -rf /home/brandon/code/earthly/pantalasa-cronos/lunar/collectors/<name>-test
rm -rf /home/brandon/code/earthly/pantalasa-cronos/lunar/policies/<name>-test

# Revert lunar-config.yml changes
cd /home/brandon/code/earthly/pantalasa-cronos
git checkout lunar/lunar-config.yml
git push
```

### Merging PRs from Worktrees

**Important:** The standard `gh pr merge` command can fail when using worktrees because it tries to checkout main locally. Use `--auto` instead:

```bash
# This may fail with "branch already in use" error:
gh pr merge <PR> --squash --delete-branch

# Use this instead:
gh pr merge <PR> --squash --auto
```

### After PR Merges

Once the PR is merged to main:

1. **Remove the worktree:**
   ```bash
   cd /home/brandon/code/earthly/lunar-lib
   git worktree remove ../lunar-lib-wt-<feature-name>
   ```

2. **Pull latest main:**
   ```bash
   git fetch origin && git pull origin main
   ```

3. **Update pantalasa-cronos to use @main:**
   
   If you added the collector/policy to `pantalasa-cronos/lunar/lunar-config.yml` during testing, update it to point to `@main`:
   
   ```yaml
   # Change from branch reference:
   # - uses: github://earthly/lunar-lib/policies/<name>@brandon/<feature>
   
   # To main:
   - uses: github://earthly/lunar-lib/policies/<name>@main
   ```
   
   ```bash
   cd /home/brandon/code/earthly/pantalasa-cronos
   # Edit lunar/lunar-config.yml to use @main
   git add lunar/lunar-config.yml
   git commit -m "Update <name> to use @main after merge"
   git push
   ```

3. **Delete the remote branch (optional):**
   ```bash
   git push origin --delete brandon/<feature-name>
   ```

---

## 7. PR Workflow

### Before Committing

1. **Complete the Pre-Push Checklist** above (tested on 3+ components, skip behavior, no hardcoded values, etc.)

2. **Run CI checks locally** — Same targets GitHub Actions runs:
   ```bash
   cd /home/brandon/code/earthly/lunar-lib  # Or your worktree
   
   # Validate README structure and landing page metadata
   earthly +lint
   
   # Build images (optional, but catches Earthfile errors)
   earthly +all --VERSION=test
   ```
   
   **What `+lint` validates:**
   - README.md structure (required sections, formatting)
   - `lunar-collector.yml` / `lunar-policy.yml` landing page metadata
   - Required fields: `display_name`, `long_description`, `category`, `status`, `keywords`
   
   Running these locally catches most CI failures before you push.

### Pre-Push Checklist

Before pushing your branch, verify all of the following:

- [ ] **Tested on 3+ components** — Run `lunar collector dev` / `lunar policy dev` against at least 3 diverse components (e.g., Go, Node, Python). Don't just test the happy path.
- [ ] **Results match expectations** — Compare actual output against the expected results from the implementation plan. If results differ, investigate before pushing.
- [ ] **Skip behavior verified** — Test against a component where the collector hasn't run or the data doesn't apply. The policy should skip gracefully, not error.
- [ ] **Collector output inspected** — For new collectors, run `lunar collector dev` with `--verbose` and verify the Component JSON paths and values are correct before writing policies against them.
- [ ] **No hardcoded values** — `grep -r 'earthly.atlassian\|brandon@\|pantalasa' collectors/<name>/ policies/<name>/` should return nothing. Use inputs and secrets instead.
- [ ] **Correct Docker image** — `default_image` must be `earthly/lunar-lib:base-main` (or `earthly/lunar-lib:<name>-main` for custom images). NOT `earthly/lunar-scripts:1.0.0` and NOT a temporary test tag.
- [ ] **Correct `lunar_policy` version** — `requirements.txt` uses the version specified in the plan or the latest stable version.
- [ ] **README exists** — Both collectors and policies need a `README.md`.
- [ ] **Only intended files staged** — Run `git diff --name-only main` and verify no temp files, test configs, or unrelated changes are included.
- [ ] **Edge cases tested** — Verify the 2-3 edge cases listed in the implementation plan (e.g., empty data, missing fields, invalid input).

### Create Draft PR

```bash
git add .
git commit -m "Add <feature-name> policy/collector"
git push -u origin brandon/<feature-name>

gh pr create --draft --title "Add <feature-name>" --body "Description..."

# Trigger CodeRabbit review while still in draft
gh pr comment <PR-number> --body "@coderabbitai review"
```

**Important:** Always trigger CodeRabbit in draft mode so you can address its comments *before* marking the PR ready for human review. Wait ~60 seconds after commenting, then check for review comments.

### PR Descriptions (lunar-lib)

Focus on **architecture and design decisions**, not file lists or code examples.

**Structure:**
1. **One-liner** — What does this add?
2. **Architecture** — Components/sub-collectors and their purpose (use tables)
3. **Data normalization** — What's normalized (tool-agnostic) vs native (tool-specific)?
4. **Category routing** — How are results categorized? (for collectors writing to multiple paths)
5. **Tested** — What you actually tested and outcomes (e.g., "PR on pantalasa/backend → policy passes")

**Do:**
- Explain *why* architecture decisions were made
- Show how normalization enables tool-agnostic policies
- Include tested results with ✅/❌ outcomes

**Don't:**
- List files (reviewers can see the diff)
- Include code examples (save for README)
- Over-explain obvious things

**Signature:** Always end with `🤖 *This PR was implemented by an AI agent.*` so reviewers know.

**PR Comments:** When commenting on PRs (replying to reviews, etc.), also sign with 🤖 so it's clear the response is from an AI agent, not the human account owner.

### Monitor GitHub Actions

After pushing:
1. Check GitHub Actions for CI failures
2. Fix errors automatically without waiting to be asked
3. Push fixes as additional commits

### Re-Testing After PR Changes

If you make changes to the code after opening the PR (fixing CI, addressing review comments, etc.), **re-test your work**. Use judgment on scope:

| Change Type | Re-Test Scope |
|-------------|---------------|
| Typo fix, comment change | No re-test needed |
| YAML config fix (keywords, metadata) | CI pass is sufficient |
| Logic change in policy/collector | Run `lunar policy dev` or `lunar collector dev` on 1-2 components |
| Major refactor, new assertions | Full re-test in pantalasa-cronos |
| Changed Docker image/dependencies | Rebuild image, full re-test |

**Quick re-test (most common):**

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar

# For policies - test on one relevant component
LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
  lunar policy dev <plugin>.<check> --component github.com/pantalasa-cronos/backend

# For collectors - verify output looks correct
LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
  lunar collector dev <plugin>.<sub> --component github.com/pantalasa-cronos/backend
```

If the change affects multiple checks/sub-collectors, test each one. Don't skip re-testing just because CI passes — CI validates syntax and structure, not correctness.

### Common CI Issues

| Issue | Fix |
|-------|-----|
| Missing `requirements.txt` | Add `lunar-policy==0.2.2` |
| Syntax error in YAML | Validate with `yq` or online tool |
| Missing keywords | Add `keywords: []` to each sub-collector/policy |
| Missing landing_page fields | Check required fields in reference docs |
| `related` references non-existent policy | Update collector `lunar-collector.yml` to point to renamed/consolidated policy |

---

## 8. CodeRabbit Review Handling

**Trigger CodeRabbit on draft PRs** by commenting `@coderabbitai review`. This lets you address review comments before marking the PR ready for human review. CodeRabbit won't auto-review drafts, but it will respond to the explicit trigger.

```bash
# Trigger review on a draft PR
gh pr comment <PR-number> --body "@coderabbitai review"
```

### Known False Positives

**"Missing `return` after `c.skip()`"**

CodeRabbit may suggest adding `return c` after `c.skip()`. **This is wrong.** The `c.skip()` method raises a `SkippedError` exception which exits the `with` block. Ignore this suggestion.

**Stale comments after force-push**

If you remove files from a PR via force-push, CodeRabbit comments on those files become stale but still appear. These can be safely ignored.

### Valid Feedback to Watch For

**"Unreachable skip logic"**

If CodeRabbit says `skip()` is unreachable after `c.exists()`, **it's correct**. This is a real bug — see "Data Existence Checks" in Section 4. The fix is to use `c.get_node(path).exists()` instead.

### Responding to CodeRabbit Comments

**Always reply to CodeRabbit comments** — it learns from feedback, so keeping it updated improves future reviews.

| Outcome | Action |
|---------|--------|
| **Addressed** | Reply explaining what you fixed, then resolve the thread |
| **Won't fix** | Reply with justification, then resolve the thread |
| **False positive** | Reply explaining why, then resolve the thread |

**Wait for follow-up responses.** After replying to CodeRabbit or pushing fixes:
- Wait 2-3 minutes for CodeRabbit to process new commits and post follow-up comments
- Check for new comments before considering the review complete
- CodeRabbit often acknowledges your fixes or asks clarifying questions
- Same applies to human reviewers — don't assume silence means approval

**Reply and resolve commands:**

```bash
# 1. Reply to the comment
gh api repos/earthly/lunar-lib/pulls/<PR>/comments/<comment-id>/replies \
  -X POST -f body="Fixed in <commit-sha>: <brief description of fix>

🤖"

# 2. Resolve the thread (requires GraphQL — get thread ID from comment)
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<thread-id>"}) { thread { isResolved } } }'
```

**Finding comment and thread IDs:**

```bash
# List all review comments with IDs
gh api repos/earthly/lunar-lib/pulls/<PR>/comments --jq '.[] | "\(.id) | \(.path):\(.line) | \(.body | split("\n")[0])"'
```

The thread ID is in the comment's `node_id` field (for GraphQL) or can be found in the PR review threads.

### Self-Review Before Opening/Updating PR

**Always do a self-review** before opening a PR or after making extensive changes. This catches inconsistencies that CodeRabbit and CI won't detect.

**Self-Review Checklist:**

| Check | What to Look For |
|-------|------------------|
| **README ↔ Code consistency** | Do examples show realistic data? Do failure messages match the code? |
| **lunar-policy.yml descriptions** | Are all descriptions consistent in style? Do they accurately describe behavior? |
| **Skip vs Fail behavior** | Is it documented correctly? Do examples show when each happens? |
| **Examples include required data** | If checks require `.lang.*`, do examples show it? |
| **Inputs documentation** | Are all inputs documented with defaults and descriptions? |

**What to re-read:**
1. Your code files — look for patterns you repeated that might be inconsistent
2. README.md — read every example and failure message against the code
3. lunar-policy.yml or lunar-collector.yml — check descriptions match actual behavior
4. Related ai-context docs — ensure you followed the conventions

**Common issues self-review catches:**
- Documentation saying "skips" when code actually "fails"
- Examples missing required fields (e.g., `.lang` for language-aware policies)
- Inconsistent descriptions between policies in the same plugin
- Unreachable code after `c.skip()` (the `return c` pattern)
- `int()` vs `float()` for numeric inputs that could be decimals

**When to self-review:**
- Before creating a draft PR
- After addressing multiple CodeRabbit comments
- After any refactor that changed behavior
- Before marking PR ready for human review

### Making PR Ready for Review

When user says "make PR ready for review":

1. **Mark as ready:**
   ```bash
   gh pr ready <PR-number> --repo earthly/lunar-lib
   ```

2. **Assign reviewer:**
   ```bash
   gh api repos/earthly/lunar-lib/pulls/<PR-number>/requested_reviewers \
     -X POST -f 'reviewers[]=<username>'
   ```

3. **Wait for CodeRabbit:** ~60 seconds for review

4. **Present comments to user:**
   - 🔴 Critical — Must fix
   - 🟠 Medium — Should discuss
   - 🟡 Minor — Can skip with justification

5. **For skipped issues, resolve with comment:**
   ```bash
   # Reply to comment
   gh api repos/earthly/lunar-lib/pulls/<PR>/comments/<comment-id>/replies \
     -X POST -f body="<justification>"
   
   # Resolve thread (requires GraphQL)
   gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<id>"}) { thread { isResolved } } }'
   ```

### People Aliases for Reviewers

- **Vlad** → `vladaionescu`
- **Mike** → `mikejholly`

---

## 9. Quick Reference

### File Checklist - Collector

- [ ] `lunar-collector.yml` with landing_page
- [ ] Main script(s) (`.sh`)
- [ ] `README.md`
- [ ] `assets/<name>.svg` icon
- [ ] Keywords on each sub-collector

### File Checklist - Policy

- [ ] `lunar-policy.yml` with landing_page
- [ ] Check scripts (`.py`)
- [ ] `requirements.txt` with `lunar-policy==0.2.2`
- [ ] `README.md`
- [ ] `assets/<name>.svg` icon
- [ ] Keywords on each policy
- [ ] Unit tests (optional but recommended)

### Common Paths

```
/home/brandon/code/earthly/lunar-lib           # Main repo
/home/brandon/code/earthly/lunar-lib-wt-*      # Worktrees
/home/brandon/code/earthly/pantalasa-cronos    # Test environment
/home/brandon/code/earthly/earthly-agent-config # This config
```
