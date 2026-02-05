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
1. **Verify staged files** before committing (`git diff --name-only main`)
2. **Run unit tests locally** before pushing (if tests exist)
3. Commit and push changes
4. Create a **draft PR** initially
5. Watch GitHub Actions for failures
6. Fix CI errors automatically by pushing additional commits

**For lunar-lib PRs:** See detailed PR description guidelines, CodeRabbit handling, and testing in [LUNAR-PLUGIN-GUIDE.md](LUNAR-PLUGIN-GUIDE.md).

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
