# Lunar Plugin Development Guide

Complete guide for AI agents building collectors and policies in lunar-lib.

---

## 1. Before You Start

### Pull Latest Guidelines

```bash
cd ~/code/earthly/earthly-agent-config && git pull
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

default_image: earthly/lunar-scripts:1.0.0
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

default_image: earthly/lunar-scripts:1.0.0

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
- Skip gracefully when data isn't available (collector may not have run)
- Never call `get_value()` without first checking `exists()`
- **`c.skip()` raises `SkippedError`** — no `return` needed after it
- **There is no `c.succeed()` method** — checks auto-pass if no assertions fail

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
1. Find the official SVG logo (check the project's brand assets or GitHub)
2. Simplify if needed (remove backgrounds, reduce complexity)
3. Ensure transparent background

For custom icons:
1. Use an AI image generator or icon tool to create a concept
2. Convert to clean SVG (tools like Figma, Inkscape, or online converters)
3. Manually clean up: remove backgrounds, ensure transparency
4. Test on dark background before committing

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

**Revert the image tag** in `lunar-collector.yml` before committing:

```yaml
# In lunar-lib worktree (NOT pantalasa-cronos)
version: 0
name: my-collector
default_image: earthly/lunar-lib:<collector-name>-$VERSION  # Production pattern
# Or if using base: earthly/lunar-scripts:1.0.0
```

The CI will build and push the proper image when the PR merges.

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

#### Step 1: Copy Files to Test Directory

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

#### Step 1: Copy Files to Test Directory

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

#### If No Relevant Test Components Exist

If none of the components have the data your policy needs:

1. **Stop and discuss with the user**
2. **Plan together:**
   - Can we add test data to an existing component?
   - Should we create a dedicated test component?
   - Is there another way to validate the policy?

---

### Unit Tests (For Agent Confidence Only)

Unit tests help you validate logic before integration testing. **Do NOT commit unit tests to lunar-lib** — they are for your own confidence during development.

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

### After PR Merges

Once the PR is merged to main:

1. **Remove the worktree:**
   ```bash
   cd /home/brandon/code/earthly/lunar-lib
   git worktree remove ../lunar-lib-wt-<feature-name>
   ```

2. **Update pantalasa-cronos to use @main:**
   
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

1. **Verify staged files:**
   ```bash
   git diff --name-only main
   ```
   Only intended files should be listed. Don't commit:
   - Temporary plan files
   - Test configs from pantalasa-cronos
   - Unrelated changes

2. **Run unit tests (if they exist):**
   ```bash
   python -m pytest policies/<name>/test_*.py -v
   ```

3. **Run CI checks locally** — Same targets GitHub Actions runs:
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

### Create Draft PR

```bash
git add .
git commit -m "Add <feature-name> policy/collector"
git push -u origin brandon/<feature-name>

gh pr create --draft --title "Add <feature-name>" --body "Description..."
```

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

---

## 8. CodeRabbit Review Handling

### Known False Positives

**"Missing `return` after `c.skip()`"**

CodeRabbit may suggest adding `return c` after `c.skip()`. **This is wrong.** The `c.skip()` method raises a `SkippedError` exception which exits the `with` block. Ignore this suggestion.

**Stale comments after force-push**

If you remove files from a PR via force-push, CodeRabbit comments on those files become stale but still appear. These can be safely ignored.

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
