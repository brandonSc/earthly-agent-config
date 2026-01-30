# Lunar Development Workspace

Personal workspace notes for AI agents working on Lunar collectors and policies.

---

## Agent Preferences & Guidelines

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
  git add AGENTS.md && git commit -m "Fix: <what you fixed>" && git push
  ```

### Working on lunar-lib
When working on collectors or policies in lunar-lib, agents should:

1. **Update main first** — Before starting any work, pull the latest changes on the main branch to ensure you're working from the most recent code.

2. **Read the ai-context documentation** — Read `lunar-lib/ai-context/` docs before implementing. This includes `about-lunar.md`, `core-concepts.md`, `collector-reference.md`, `policy-reference.md`, and relevant `component-json/` files.

3. **Use git worktrees** — Create a worktree for each feature so multiple agents can work in parallel without conflicts.

4. **Test your work** — Either with unit tests or by testing in the `pantalasa/lunar` environment (see sections below).

5. **Create draft PRs and iterate** — Once confident the implementation works:
   - Push commits directly to the branch
   - Create a draft PR using `gh pr create --draft`
   - Monitor GitHub Actions for CI errors
   - Fix any errors automatically without waiting to be asked

### PR Workflow (General)
When asked to open PRs (for any repo), follow this flow:
1. Commit and push changes
2. Create a **draft PR** initially
3. Watch GitHub Actions for failures
4. Fix CI errors automatically by pushing additional commits

---

## Repository Layout

| Directory | Purpose |
|-----------|---------|
| `lunar-lib/` | Main repo for open-source collectors and policies |
| `lunar-lib-wt-*/` | Git worktrees for parallel development |
| `pantalasa/` | Test environment with sample components |
| `lunar/` | Lunar CLI and core platform |
| `skills/` | Agent skills for Lunar, Earthly, and related tools |
| `skills-internal/` | Internal agent skills (Linear tickets, etc.) |

---

## Agent Skills

Use skills from [earthly/skills](https://github.com/earthly/skills) for detailed implementation guidance. Skills are at `/home/brandon/code/earthly/skills/skills/`.

| Skill | When to Use | Read Documentation |
|-------|-------------|-------------------|
| `lunar-collector` | Creating Lunar collectors (Bash scripts that gather SDLC metadata) | `cat /home/brandon/code/earthly/skills/skills/lunar-collector/SKILL.md` |
| `lunar-policy` | Creating Lunar policies (Python scripts that enforce standards) | `cat /home/brandon/code/earthly/skills/skills/lunar-policy/SKILL.md` |
| `lunar-sql` | Querying Lunar's SQL API for components, checks, PRs, domains | `cat /home/brandon/code/earthly/skills/skills/lunar-sql/SKILL.md` |
| `earthfile` | Writing Earthfiles for containerized builds | `cat /home/brandon/code/earthly/skills/skills/earthfile/SKILL.md` |

**Before implementing collectors or policies**, read the relevant skill's SKILL.md and references/ folder.

---

## Git Worktrees for Parallel Development

When working on multiple policies or collectors simultaneously, use git worktrees instead of multiple clones:

```bash
cd /home/brandon/code/earthly/lunar-lib

# Create a worktree for a new policy
git worktree add ../lunar-lib-wt-<feature-name> -b brandon/<feature-name>

# List all worktrees
git worktree list

# Remove a worktree after merging
git worktree remove ../lunar-lib-wt-<feature-name>
```

Each worktree is a separate working directory on its own branch, sharing the same `.git` state. This saves disk space and keeps branches in sync automatically.

---

## Test Environment (pantalasa)

The **pantalasa** repo at `/home/brandon/code/earthly/pantalasa` provides a test environment with:

- Pre-configured Lunar Hub connection (`lunar.demo.earthly.dev`)
- Sample components with real data for testing
- Local plugin directories for iterative development

### Test Components Available

| Component | Language | Tags | Good For Testing |
|-----------|----------|------|------------------|
| `github.com/pantalasa/backend` | Go | backend, go, SOC2 | Go collectors/policies, lint, dependencies |
| `github.com/pantalasa/frontend` | Node.js | frontend, nodejs | Node.js collectors/policies |
| `github.com/pantalasa/auth` | Python | backend, python, SOC2 | Python collectors/policies |
| `github.com/pantalasa/spring-petclinic` | Java | backend, java, SOC2 | Java collectors/policies |

### Test Token

```bash
export LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643
```

This token authenticates with the demo Lunar Hub for development testing.

---

## Testing Policies

1. **Copy your policy to the pantalasa test directory:**

   ```bash
   cp -r policies/<policy-name>/* \
     /home/brandon/code/earthly/pantalasa/lunar/policies/<policy-name>-test/
   ```

2. **Add a policy reference to pantalasa's `lunar/lunar-config.yml`:**

   ```yaml
   policies:
     - uses: ./policies/<policy-name>-test
       name: <policy-name>-test
       on: [go]  # or appropriate selector
       enforcement: draft
       with:
         # your policy inputs here
   ```

3. **Run the policy in dev mode:**

   ```bash
   cd /home/brandon/code/earthly/pantalasa/lunar
   LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
     lunar policy dev <policy-name>-test \
     --component github.com/pantalasa/backend
   ```

4. **Iterate:** After each code change, copy the updated files and re-run the dev command.

---

## Testing Collectors

1. **Copy your collector to the pantalasa test directory:**

   ```bash
   cp -r collectors/<collector-name>/* \
     /home/brandon/code/earthly/pantalasa/lunar/collectors/<collector-name>-test/
   ```

2. **Add a collector reference to pantalasa's `lunar/lunar-config.yml`:**

   ```yaml
   collectors:
     - uses: ./collectors/<collector-name>-test
       on: ["domain:engineering"]
   ```

3. **Run the collector in dev mode:**

   The collector name format is `<plugin-name>.<sub-collector-name>`. The plugin name comes from `name:` in the `lunar-collector.yml`, and sub-collector names come from the `collectors:` array in that file.

   ```bash
   cd /home/brandon/code/earthly/pantalasa/lunar
   LUNAR_HUB_TOKEN=df11a0951b7c2c6b9e2696c048576643 \
     lunar collector dev <plugin-name>.<sub-collector-name> \
     --component github.com/pantalasa/backend
   ```

   **Examples:**
   - `lunar collector dev readme.readme --component github.com/pantalasa/frontend`
   - `lunar collector dev github.branch-protection --component github.com/pantalasa/frontend`
   - `lunar collector dev golang.golang --component github.com/pantalasa/backend`

   **Useful flags:**
   - `--verbose` — Show detailed output
   - `--secrets "KEY=value"` — Pass secrets to the collector
   - `--use-system-runtime` — Run without Docker (requires local dependencies like jq)

4. **View collected data:** The dev command outputs the Component JSON that would be written.

---

## PR Workflow

After testing is complete:

```bash
# From your worktree
git add .
git commit -m "Add <feature-name> policy/collector"
git push -u origin brandon/<feature-name>

# Create a draft PR for review
gh pr create --draft --title "Add <feature-name>" --body "Description..."
```

---

## Reference Documentation

For detailed implementation guides, see `lunar-lib/ai-context/`:

| Document | Purpose |
|----------|---------|
| `about-lunar.md` | High-level overview of Lunar |
| `core-concepts.md` | Architecture and key entities |
| `collector-reference.md` | How to write collectors |
| `policy-reference.md` | How to write policies |
| `component-json/conventions.md` | Schema design principles |
| `guardrail-specs/` | Specifications for guardrails to implement |

---

## Creating Linear Tickets

When the user asks to create a Linear ticket, use the **linear-tickets** skill from [earthly/skills-internal](https://github.com/earthly/skills-internal).

**Read the skill documentation:**
```bash
cat /home/brandon/code/earthly/skills-internal/skills/linear-tickets/SKILL.md
```

**Quick reference:**
- Scripts: `/home/brandon/code/earthly/skills-internal/skills/linear-tickets/scripts/`
- Create ticket: `./create-linear-ticket.sh "Title" "Description"`
- Attach image: `./attach-linear-image.sh ENG-123 /path/to/image.png`
- Requires: `LINEAR_API_TOKEN` env var, `jq`
- Default team: ENG
- Always return links as markdown: `[ENG-123](https://linear.app/earthly-technologies/issue/ENG-123/slug)`
- Convert Windows paths to WSL: `C:\Users\...` → `/mnt/c/Users/...`
