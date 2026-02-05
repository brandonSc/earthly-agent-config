# Lunar Development Workspace

Personal workspace notes for AI agents working on Lunar collectors and policies.

---

## Agent Preferences & Guidelines

### People Aliases
When the user refers to these names, use the corresponding GitHub username:
- **Vlad** → `vladaionescu`
- **Mike** → `mikejholly`

### Before Starting Any Work
- **Pull this config repo** — Run `cd ~/code/earthly/earthly-agent-config && git pull` to get the latest workspace guidelines.

### Code Style
- **Be concise.** Write clean, minimal code. Avoid over-engineering.

### Improving This Document (Self-Improvement)
- **Always refine these instructions.** When something doesn't work as documented, fix it immediately. This is critical for self-improvement over time.
- Examples of what to update:
  - Commands that fail or have wrong paths
  - Missing dependencies or prerequisites
  - Workarounds you discovered
  - Better approaches than what's documented
- After fixing, commit and push so future agents benefit:
  ```bash
  cd ~/code/earthly/earthly-agent-config
  git add . && git commit -m "Fix: <what you fixed>" && git push
  ```

### Working on lunar-lib

**Read the full guide:** [LUNAR-PLUGIN-GUIDE.md](LUNAR-PLUGIN-GUIDE.md)

Summary of workflow:
1. **Update main first** — Pull latest changes before starting work
2. **Read the ai-context docs** — `lunar-lib/ai-context/` contains implementation guides
3. **Use git worktrees** — One worktree per feature for parallel development
4. **Test your work** — Unit tests + integration tests in `pantalasa-cronos`
5. **Create draft PRs** — Push, create draft PR, monitor GitHub Actions, fix errors automatically

### PR Workflow (General)
When asked to open PRs (for any repo), follow this flow:
1. **Verify staged files** before committing:
   ```bash
   git diff --name-only main  # Check what will be in the PR
   ```
   Only intended files should be listed. Don't commit temporary plan files.
2. **Run unit tests locally** before pushing (if tests exist)
3. Commit and push changes
4. Create a **draft PR** initially
5. Watch GitHub Actions for failures
6. Fix CI errors automatically by pushing additional commits

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

### CodeRabbit Notes

**Important:** CodeRabbit only reviews PRs that are **not in draft**. It will show "Review skipped" for draft PRs. Mark PR as ready (`gh pr ready <number>`) to trigger CodeRabbit review.

Known false positives:

- **"Missing `return` after `c.skip()`"** — Wrong. `c.skip()` raises `SkippedError` which exits the `with` block. Ignore this.
- **Stale comments after force-push** — Comments on removed files can be ignored.

**Valid feedback to watch for:**
- **Unreachable skip logic** — If CodeRabbit says skip() is unreachable after `c.exists()`, it's correct. See "Data Existence Checks" below.

### Data Existence Checks in Policies

This is a common source of bugs. There are **two different patterns** for checking if data exists:

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
if not c.get_node(".testing").exists():
    c.skip("No test execution data found")
    return c
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

**Good example:** See `lunar-lib/policies/testing/passing.py` — uses `get_node().exists()` for skip logic, then `assert_true()` for the actual check.

### Policy Style Guidelines

**Naming:** README title AND `display_name` must end with "Guardrails" (e.g., "Testing Guardrails"), not "Policies".

**Descriptions in lunar-policy.yml should be user-focused:**
- ❌ BAD: "Skips if pass/fail data is not available (some collectors only report execution, not results)"
- ✅ GOOD: "Ensures all tests pass. Skips if project does not contain a specified language."

Move implementation details (data paths, skip conditions, collector specifics) to README only.

### Debugging Tips

- **Branch refs may cache** — If `@brandon/branch` shows stale behavior, copy to `./policies/<name>-test/` instead
- **Debug prints** — Add to the test copy, not the source
- **Docker required** — `lunar policy dev` needs Docker Desktop running

### Testing Policy/Collector Behavior in Real PRs

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

#### Test Components

| Component | Has Snyk | Good For Testing |
|-----------|----------|------------------|
| `pantalasa/backend` | ✅ Yes | SCA policies passing, Go policies |
| `pantalasa/whoami` | ❌ No | SCA policies failing (no scanner configured) |
| `pantalasa/frontend` | ✅ Yes | Node.js policies |
| `pantalasa/auth` | ✅ Yes | Python policies |

#### Cleanup After Testing

```bash
# Close test PR
gh pr close <pr-number>

# Delete test branch
git checkout main
git branch -D test/<description>
git push origin --delete test/<description>
```

---

## Repository Layout

| Directory | Purpose |
|-----------|---------|
| `lunar-lib/` | Main repo for open-source collectors and policies |
| `lunar-lib-wt-*/` | Git worktrees for parallel development |
| `pantalasa-cronos/` | **Primary test environment** (use this, not `pantalasa`) |
| `pantalasa/` | Legacy test environment (may have demos running) |
| `lunar/` | Lunar CLI and core platform |
| `skills/` | Agent skills for Lunar, Earthly, and related tools |
| `skills-internal/` | Internal agent skills (Linear tickets, etc.) |

---

## Agent Skills

Use skills from [earthly/skills](https://github.com/earthly/skills) and [earthly/skills-internal](https://github.com/earthly/skills-internal) for detailed implementation guidance.

### Before Using Any Skill

**Always pull and reinstall skills** to ensure you have the latest documentation:

```bash
# Public skills (Lunar, Earthfiles)
cd /home/brandon/code/earthly/skills && git pull && earthly +install-skills

# Internal skills (Linear tickets)
cd /home/brandon/code/earthly/skills-internal && git pull && earthly +install-skills
```

### Available Skills

| Skill | Repo | When to Use |
|-------|------|-------------|
| `lunar-collector` | skills | Creating Lunar collectors |
| `lunar-policy` | skills | Creating Lunar policies |
| `lunar-sql` | skills | Querying Lunar's SQL API |
| `earthfile` | skills | Writing Earthfiles |
| `linear-tickets` | skills-internal | Creating Linear tickets |

### Reading Skill Documentation

```bash
# Public skills
cat /home/brandon/code/earthly/skills/skills/<skill-name>/SKILL.md

# Internal skills
cat /home/brandon/code/earthly/skills-internal/skills/<skill-name>/SKILL.md
```

---

## Quick Reference

### Test Environment

Use `pantalasa-cronos` (not `pantalasa`):

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/lunar
export LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643
# Hub: cronos.demo.earthly.dev
```

### Git Worktrees

```bash
cd /home/brandon/code/earthly/lunar-lib

# Create worktree
git worktree add ../lunar-lib-wt-<feature> -b brandon/<feature>

# List worktrees
git worktree list

# Remove after merge
git worktree remove ../lunar-lib-wt-<feature>
```

### Testing with Branch References

Instead of copying files, reference your branch in `lunar-config.yml`:

```yaml
# Policy
- uses: github://earthly/lunar-lib/policies/<name>@brandon/<feature>

# Collector
- uses: github://earthly/lunar-lib/collectors/<name>@brandon/<feature>
```

Then run dev commands:

```bash
lunar policy dev <plugin>.<check> --component github.com/pantalasa-cronos/backend
lunar collector dev <plugin>.<sub> --component github.com/pantalasa-cronos/backend
```

---

## Reference Documentation

For detailed implementation guides:
- **This repo:** [LUNAR-PLUGIN-GUIDE.md](LUNAR-PLUGIN-GUIDE.md) — Complete collector/policy development guide
- **lunar-lib:** `ai-context/` — Platform documentation
- **Skills:** `SKILL.md` files in skills repos

---

## Creating Linear Tickets

Use the **linear-tickets** skill from [earthly/skills-internal](https://github.com/earthly/skills-internal).

```bash
cat /home/brandon/code/earthly/skills-internal/skills/linear-tickets/SKILL.md
```

Quick reference:
- Create: `./create-linear-ticket.sh "Title" "Description"`
- Attach image: `./attach-linear-image.sh ENG-123 /path/to/image.png`
- Requires: `LINEAR_API_TOKEN` env var, `jq`
- Return links as markdown: `[ENG-123](https://linear.app/earthly-technologies/issue/ENG-123/slug)`
