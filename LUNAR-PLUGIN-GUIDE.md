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

## 5. Testing in pantalasa-cronos

Use `pantalasa-cronos` for testing (not `pantalasa` which may have demos running).

### Hub & Token

```bash
# Hub: cronos.demo.earthly.dev
export LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643
```

### Available Test Components

| Component | Language | Tags |
|-----------|----------|------|
| `github.com/pantalasa-cronos/backend` | Go | go, SOC2 |
| `github.com/pantalasa-cronos/frontend` | Node.js | node |
| `github.com/pantalasa-cronos/auth` | Python | python, SOC2 |
| `github.com/pantalasa-cronos/kafka-go` | Go | go, kafka |
| `github.com/pantalasa-cronos/hadoop` | Java | java, SOC2 |
| `github.com/pantalasa-cronos/spark` | Java | java, SOC2 |

### Branch Reference Method (Preferred)

Instead of copying files, reference your branch directly:

1. **Push changes to lunar-lib branch:**
   ```bash
   cd /home/brandon/code/earthly/lunar-lib-wt-<feature>
   git add . && git commit -m "Add <feature>" && git push -u origin brandon/<feature>
   ```

2. **Update pantalasa-cronos lunar-config.yml:**
   ```yaml
   # For policies
   policies:
     - uses: github://earthly/lunar-lib/policies/<name>@brandon/<feature>
       on: ["domain:engineering"]
       enforcement: draft
   
   # For collectors
   collectors:
     - uses: github://earthly/lunar-lib/collectors/<name>@brandon/<feature>
       on: ["domain:engineering"]
   ```

3. **Run dev command:**
   ```bash
   cd /home/brandon/code/earthly/pantalasa-cronos/lunar
   LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
     lunar policy dev <plugin>.<check> --component github.com/pantalasa-cronos/backend
   ```

4. **Iterate:** Push new commits, re-run dev command. No copying needed!

5. **After PR merges:** Update config back to `@main`

**Note:** Commit SHA references don't work — only branch/tag names.

### Dev Command Examples

```bash
# Policy
lunar policy dev golang.go-mod-exists --component github.com/pantalasa-cronos/backend

# Collector
lunar collector dev snyk.github-app --component github.com/pantalasa-cronos/backend
```

### Useful Flags

- `--verbose` — Show detailed output
- `--secrets "KEY=value"` — Pass secrets to collector
- `--use-system-runtime` — Run without Docker (requires local dependencies)

---

## 6. PR Workflow

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

### Common CI Issues

| Issue | Fix |
|-------|-----|
| Missing `requirements.txt` | Add `lunar-policy==0.2.2` |
| Syntax error in YAML | Validate with `yq` or online tool |
| Missing keywords | Add `keywords: []` to each sub-collector/policy |
| Missing landing_page fields | Check required fields in reference docs |

---

## 7. CodeRabbit Review Handling

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

## 8. Quick Reference

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
