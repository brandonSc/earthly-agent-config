# Lunar Plugin PR Playbook

Step-by-step playbook for AI agents (Devin, Claude, etc.) to create lunar-lib collector and policy PRs end-to-end. This is a **bot-mode** workflow — the agent works autonomously through each phase, pausing only at explicit review gates.

---

## Overview

Every lunar-lib plugin PR follows three phases:

| Phase | What you do | Gate |
|-------|------------|------|
| **1. Spec PR** | Create YAML manifest, README, SVG icon. Open draft PR with design + testing plan. | Humans review spec. Wait for "go ahead." |
| **2. Implementation** | Write shell/python scripts. Test locally. Post test results on the PR. | Humans review code + results. Wait for approval. |
| **3. Merge** | Address review feedback. CI green. Merge when approved. | Approval from reviewers. |

**Never skip Phase 1.** The spec is cheap to iterate on. Code is expensive to throw away.

---

## Before You Start

### 1. Pull latest guidelines

```bash
cd ~/code/earthly/earthly-agent-config && git pull
```

### 2. Read the docs

Read these files in `lunar-lib/ai-context/` before doing anything:

| File | Why |
|------|-----|
| `about-lunar.md` | What Lunar is |
| `core-concepts.md` | Architecture |
| `collector-reference.md` | How collectors work (if building a collector) |
| `policy-reference.md` | How policies work (if building a policy) |
| `component-json/conventions.md` | **Schema design rules — critical.** Read the "Presence Detection" and "Anti-Pattern: Boolean Fields" sections carefully. |
| `component-json/structure.md` | All existing Component JSON paths |

### 3. Update lunar-lib

```bash
cd /home/brandon/code/earthly/lunar-lib
git checkout main && git pull origin main
```

### 4. Study the closest existing plugin

Find the most similar existing collector or policy and read every file. Understand the pattern before writing anything. Examples:

| If building... | Study this |
|----------------|-----------|
| Issue tracker collector | `collectors/jira/` |
| Security scanner collector | `collectors/semgrep/` or `collectors/snyk/` |
| Language collector | `collectors/golang/` or `collectors/java/` |
| Repo/file check policy | `policies/repo/` |
| Security policy | `policies/sast/` or `policies/sca/` |

---

## Phase 1: Spec PR

### What to produce

Three files (no implementation code):

```
collectors/<name>/
├── lunar-collector.yml    # Plugin manifest
├── README.md              # Documentation
└── assets/
    └── <name>.svg         # Icon (black fill!)
```

Or for policies:

```
policies/<name>/
├── lunar-policy.yml       # Plugin manifest
├── README.md              # Documentation
├── requirements.txt       # lunar-policy==0.2.2 (if Python)
└── assets/
    └── <name>.svg         # Icon (black fill!)
```

### YAML manifest rules

- Copy the structure from the closest existing plugin.
- `mainBash`/`mainPython` fields should reference filenames that **don't exist yet** — that's fine for the spec PR.
- Include `inputs`, `secrets`, and `example_component_json`.
- **Validate Component JSON paths** against `ai-context/component-json/conventions.md`. Common mistakes:
  - Adding boolean fields when object presence is the signal
  - Putting data under `.native` that belongs at the category level
  - Inventing new top-level categories when data fits an existing one

### README rules

Follow the template in `ai-context/collector-README-template.md` or `ai-context/policy-README-template.md`. Include:

- One-line description
- Overview (2-3 sentences)
- Collected Data table (paths, types, descriptions)
- Sub-collector/check table
- Installation YAML example
- Inputs table
- Notes on anything non-obvious

### SVG icon rules

- **Must use `fill="black"`** — not white, not colored. The website converts to white automatically. Black is visible in GitHub PR diffs.
- Source from [simple-icons](https://github.com/simple-icons/simple-icons) when possible:
  ```bash
  curl -sL "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/<name>.svg"
  ```
- Strip `<title>` tags and `role="img"`. Add `fill="black"` to all `<path>` elements.
- Wrap in a clean `<svg xmlns="http://www.w3.org/2000/svg" viewBox="...">` container.

### PR description

The draft PR description must include:

1. **What's included** — list the files
2. **Design summary** — which Component JSON paths are written, why, and how they relate to existing paths
3. **Relationship to existing plugins** — does this reuse an existing policy? Does it write to the same normalized paths as another collector?
4. **Testing plan** — what components you'll test against, expected results per component, edge cases
5. **Open questions** — anything you're unsure about (architecture, naming, path choices)
6. **`*This PR was drafted by AI.*`** at the end

### Git workflow

```bash
# Create worktree
cd /home/brandon/code/earthly/lunar-lib
git worktree add ../lunar-lib-wt-<feature> -b brandon/<feature>

# Add files
cd ../lunar-lib-wt-<feature>
mkdir -p collectors/<name>/assets  # or policies/<name>/assets
# ... create files ...

# Commit and push
git add collectors/<name>/  # or policies/<name>/
git commit -m "Add <name> collector spec (YAML + README only)"
git push origin brandon/<feature>

# Create draft PR
gh pr create --title "Add <name> collector (spec-first: YAML + README)" --body "..." --draft
```

### Then wait

**Do not proceed to Phase 2 until a human says "go ahead", "LGTM", or similar.** They may have feedback on the schema, naming, or approach.

If reviewers request changes during spec review, address them and push updates.

---

## Phase 2: Implementation

### What to produce

The actual scripts referenced in the YAML manifest:

- **Collectors:** Shell scripts (`.sh`) that use `lunar collect` to write data
- **Policies:** Python scripts (`.py`) that use `lunar_policy.Check` to assert

### Implementation rules

- **Alpine/BusyBox compatibility** — The `base-main` image uses Alpine. No GNU grep extensions (`-P`, `--include`). No gawk. Use `sed`, `find`, BusyBox-compatible patterns. See existing collectors for examples.
- **No jq in CI collectors** — CI collectors use `native` image (no jq guaranteed). Code collectors in `base-main` have jq.
- **Graceful degradation** — Missing secrets or configs should `exit 0` with a stderr message, not `exit 1`.
- **Copy helpers from similar plugins** — If the closest plugin has a `helpers.sh` with reusable logic, copy it rather than inventing new patterns.

### Testing

Test locally before pushing. For collectors:

```bash
cd /home/brandon/code/earthly/pantalasa-cronos/<component>

lunar collector dev <plugin>.<sub-collector> \
  --component github.com/pantalasa-cronos/<component> \
  --verbose \
  --secrets "SECRET_NAME=value"
```

For policies:

```bash
# First get a component JSON to test against
lunar component get-json github.com/pantalasa-cronos/<component> > /tmp/component.json

# Then test
cd /home/brandon/code/earthly/lunar-lib-wt-<feature>/policies/<name>
lunar policy dev <plugin>.<check> --component-json /tmp/component.json
```

### Post test results on the PR

After testing, comment on the PR with results:

```markdown
## Test Results

Tested against pantalasa-cronos components:

| Component | Check | Result | Notes |
|-----------|-------|--------|-------|
| backend (Go) | ticket-present | ✅ PASS | Found ENG-42 in PR title |
| frontend (Node) | ticket-present | ✅ PASS | Found ENG-15 |
| auth (Python) | ticket-valid | ⏭️ SKIP | No PR context (default branch) |
| backend (Go) | ticket-reuse | ✅ PASS | reuse_count=0 |

### Edge cases verified:
- ✅ Missing API key → graceful skip
- ✅ Invalid ticket ID → no data written
- ✅ No PR context → skips cleanly

🤖
```

### Push implementation

```bash
git add collectors/<name>/  # or policies/<name>/
git commit -m "Add <name> implementation"
git push origin brandon/<feature>
```

CI will run automatically. Fix any CI failures.

### Then wait for review

Comment on the PR tagging `@coderabbitai review` to get automated review. Address CodeRabbit feedback.

Wait for human reviewers to approve. Address their feedback. In bot mode, you may push fixes and reply directly. In interactive mode, present feedback to the user first.

---

## Phase 3: Merge

### Pre-merge checklist

- [ ] CI is green
- [ ] CodeRabbit comments addressed
- [ ] Human reviewer(s) approved
- [ ] Test results posted on PR
- [ ] No unresolved review threads

### Merge

**Never merge without explicit approval.** When approved:

```bash
gh pr merge <PR-number> --squash --delete-branch
```

### Cleanup

```bash
cd /home/brandon/code/earthly/lunar-lib
git worktree remove ../lunar-lib-wt-<feature>
```

---

## Quick Reference: Conventions

### Component JSON paths

- **Categories describe WHAT, not HOW** — `.sca`, not `.snyk`
- **Object presence = signal** for conditional collectors (no redundant booleans)
- **Explicit booleans** only when the same collector writes both `true` and `false`
- **`.native.<tool>`** for raw tool output; normalized data at category level
- **`.source`** metadata: `{tool, version, integration}`

### PR titles

- `Add <name> collector (spec-first: YAML + README)` — Phase 1
- `Add <name> implementation` — commit message for Phase 2 code
- No Linear ticket prefix needed for lunar-lib PRs (unlike lunar core)

### AI attribution

End every PR description with: `*This PR was drafted by AI.*`

Sign all PR comments with 🤖.

---

## Example: Linear Collector

For a complete worked example of this playbook, see:
- **Plan:** `lunar-lib/.agents/plans/linear-integration.md`
- **Spec PR:** https://github.com/earthly/lunar-lib/pull/72
- **Pattern:** `collectors/jira/` (the plugin this was modeled after)
