# Rust Collector & Policy — Implementation Plan

Add a Rust language plugin to lunar-lib with a collector for project metadata, dependencies, clippy, CI/CD tracking, and test coverage, plus a policy for Rust project standards.

---

## Context

Rust is a systems programming language with a unique ecosystem:
- **Cargo** is the universal build system and package manager
- **Cargo.toml** is the crate manifest, **Cargo.lock** pins resolved versions
- **Editions** (2015, 2018, 2021, 2024) control language feature availability
- **MSRV** (Minimum Supported Rust Version) declared in `Cargo.toml` via `rust-version`
- **`unsafe` blocks** bypass Rust's safety guarantees — organizations want to track/limit these
- **Clippy** is the de facto linter (analogous to golangci-lint for Go)
- **Workspaces** support multi-crate monorepos
- **Library vs Application** distinction matters for lockfile policy (Cargo convention: commit Cargo.lock for apps, not for libs)

### Design: Follow the Go/Java/Node pattern

The plugin follows the same structure as the existing language plugins:
- **Collector** at `collectors/rust/` writes to `.lang.rust.*`
- **Policy** at `policies/rust/` reads from `.lang.rust.*`
- Custom Docker image `earthly/lunar-lib:rust-main` for code collectors (needs Rust toolchain + clippy)
- CI collectors use `native` mode

---

## Pre-Implementation Steps

1. Pull latest `lunar-lib` main
2. Read `ai-context/` docs:
   - `component-json/conventions.md` — especially Language-Specific Data section
   - `component-json/structure.md` — existing `.lang.rust.*` placeholders
   - `collector-reference.md` — collector patterns, hook types
   - `policy-reference.md` — policy patterns, Check class
3. The worktree is already created: `lunar-lib-wt-rust` on branch `brandon/rust`
4. Review existing language plugins for reference:
   - `collectors/golang/` — closest analog (project, dependencies, golangci-lint, cicd, test-coverage)
   - `collectors/java/` — multi-build-system pattern
   - `policies/golang/` — version checks, file existence checks

---

## Part 1: Rust Collector (`collectors/rust`)

### File Structure

```
collectors/rust/
├── assets/
│   └── rust.svg              # Grayscale SVG icon
├── Earthfile                  # Custom image with Rust toolchain + clippy
├── lunar-collector.yml        # Collector manifest (already created — spec PR)
├── project.sh                 # Project structure detection + unsafe blocks
├── dependencies.sh            # Dependency extraction
├── clippy.sh                  # Clippy lint runner
├── cicd.sh                    # CI command tracking
├── test-coverage.sh           # Coverage extraction
└── README.md                  # (already created — spec PR)
```

### Sub-collector: `project.sh`

**Hook:** `code`

Detects and writes:
- `cargo_toml_exists` — `[ -f Cargo.toml ]`
- `cargo_lock_exists` — `[ -f Cargo.lock ]`
- `rust_toolchain_exists` — `[ -f rust-toolchain.toml ] || [ -f rust-toolchain ]`
- `clippy_configured` — `[ -f clippy.toml ] || [ -f .clippy.toml ]`
- `rustfmt_configured` — `[ -f rustfmt.toml ] || [ -f .rustfmt.toml ]`
- `edition` — parse from Cargo.toml (`grep -oP 'edition\s*=\s*"\K[^"]+' Cargo.toml`)
- `msrv` — parse `rust-version` from Cargo.toml
- `version` — from `rust-toolchain.toml` channel or `rustc --version`
- `build_systems` — always `["cargo"]`
- `is_application` — true if `[[bin]]` in Cargo.toml OR `src/main.rs` exists
- `is_library` — true if `[lib]` in Cargo.toml OR `src/lib.rs` exists
- `workspace` — if `[workspace]` section exists, extract `members` array; otherwise null
- `unsafe_blocks` — `grep -rn 'unsafe\s*{' --include='*.rs' src/` with count and locations

**Implementation notes:**
- Use `toml2json` or simple grep/sed for Cargo.toml parsing (avoid requiring full Rust toolchain for this sub-collector)
- For workspace members, parse `members = ["crate-a", "crate-b"]` from Cargo.toml
- For unsafe blocks, grep for `unsafe {` and `unsafe fn` patterns, excluding test files and comments
- Write everything as a single `lunar collect -j ".lang.rust" '{...}'`

### Sub-collector: `dependencies.sh`

**Hook:** `code`

Extracts:
- **Direct deps** from `[dependencies]` in Cargo.toml
- **Dev deps** from `[dev-dependencies]` in Cargo.toml
- **Build deps** from `[build-dependencies]` in Cargo.toml
- **Transitive deps** from Cargo.lock (if present) — the `[[package]]` entries not in Cargo.toml

**Implementation notes:**
- Parse Cargo.toml sections with awk/sed or `toml2json` if available
- For each dependency, extract name, version (or version requirement), and features
- From Cargo.lock, each `[[package]]` entry has `name`, `version`, and `source`
- Write to `.lang.rust.dependencies`

### Sub-collector: `clippy.sh`

**Hook:** `code`

Runs `cargo clippy --message-format=json` and parses the JSON output.

**Implementation notes:**
- Requires Rust toolchain with clippy component (in the custom Docker image)
- Parse JSON lines for `compiler-message` type with `level: "warning"`
- Extract: file path (relative), line, column, message, lint name
- Write normalized warnings to `.lang.rust.lint.warnings[]`
- Write raw status to `.lang.rust.native.clippy`
- Respect `$LUNAR_INPUT_clippy_args` for additional arguments
- Exit 0 even if clippy finds warnings (policy decides pass/fail)

### Sub-collector: `cicd.sh`

**Hook:** `ci-before-command` on binary `cargo`

Records every `cargo` command executed in CI along with the Rust version.

**Implementation notes:**
- `$LUNAR_HOOK_FULL_COMMAND` contains the full command
- Get Rust version from `rustc --version` (parse `rustc X.Y.Z (hash date)`)
- Append to `.lang.rust.cicd.cmds[]` array: `{cmd, version}`
- Follow the pattern in `collectors/golang/cicd.sh`

### Sub-collector: `test-coverage.sh`

**Hook:** `ci-after-command` on binary `cargo` with args matching `tarpaulin|llvm-cov|test`

Extracts coverage percentage from coverage tool output.

**Implementation notes:**
- **cargo-tarpaulin:** Look for coverage summary in stdout/stderr or `tarpaulin-report.json`
- **cargo-llvm-cov:** Look for `coverage-summary.json` or `lcov.info`
- Parse the percentage and write to `.lang.rust.tests.coverage.percentage`
- Also write to `.testing.coverage.percentage` for cross-language dashboards (optional, discuss)
- Follow the pattern in `collectors/golang/test-coverage.sh`

### Earthfile

Build a custom Docker image `earthly/lunar-lib:rust-main` with:
- Base: `earthly/lunar-lib:base-main`
- Rust toolchain (via `rustup` or `rust:slim` base)
- Clippy component
- `toml2json` or equivalent for Cargo.toml parsing
- Keep image small — use rustup minimal profile + only clippy/rustfmt components

---

## Part 2: Rust Policy (`policies/rust`)

### File Structure

```
policies/rust/
├── assets/
│   └── rust.svg                # Same icon as collector
├── lunar-policy.yml            # Policy manifest (already created — spec PR)
├── cargo_toml_exists.py
├── cargo_lock_exists.py
├── min_rust_edition.py
├── min_rust_version_cicd.py
├── clippy_clean.py
├── max_unsafe_blocks.py
└── README.md                   # (already created — spec PR)
```

### Policy: `cargo_toml_exists.py`

```python
with Check("cargo-toml-exists", "Cargo.toml must exist for Rust projects") as c:
    rust = c.get_node(".lang.rust")
    if not rust.exists():
        c.skip("Not a Rust project")
        return
    c.assert_true(c.get_value(".lang.rust.cargo_toml_exists"),
        "Cargo.toml not found. Initialize with 'cargo init' or 'cargo new <name>'")
```

### Policy: `cargo_lock_exists.py`

```python
with Check("cargo-lock-exists", "Cargo.lock must exist for applications") as c:
    rust = c.get_node(".lang.rust")
    if not rust.exists():
        c.skip("Not a Rust project")
        return

    lock_mode = c.input("lock_mode", "auto")

    if lock_mode == "none":
        c.skip("Cargo.lock check disabled (lock_mode=none)")
        return

    has_lock = c.get_value(".lang.rust.cargo_lock_exists")
    is_app = c.get_value(".lang.rust.is_application")
    is_lib = c.get_value(".lang.rust.is_library")

    if lock_mode == "auto":
        if is_lib and not is_app:
            c.skip("Cargo.lock not required for library crates")
            return
        c.assert_true(has_lock,
            "Cargo.lock not found. Applications should commit Cargo.lock for reproducible builds. Run 'cargo generate-lockfile' to create it.")
    elif lock_mode == "required":
        c.assert_true(has_lock,
            "Cargo.lock not found. Run 'cargo generate-lockfile' to create it.")
    elif lock_mode == "forbidden":
        c.assert_false(has_lock,
            "Cargo.lock should not be committed. Remove it from version control.")
```

### Policy: `min_rust_edition.py`

```python
EDITION_ORDER = ["2015", "2018", "2021", "2024"]

with Check("min-rust-edition", "Rust edition meets minimum requirement") as c:
    rust = c.get_node(".lang.rust")
    if not rust.exists():
        c.skip("Not a Rust project")
        return

    edition = c.get_value(".lang.rust.edition")
    if not edition:
        c.fail("Rust edition not detected. Set 'edition' in Cargo.toml.")
        return

    min_edition = c.input("min_rust_edition", "2021")

    if edition not in EDITION_ORDER or min_edition not in EDITION_ORDER:
        c.fail(f"Unknown edition '{edition}' or minimum '{min_edition}'")
        return

    if EDITION_ORDER.index(edition) < EDITION_ORDER.index(min_edition):
        c.fail(f"Rust edition {edition} is below minimum {min_edition}. "
               f"Update edition in Cargo.toml to '{min_edition}' or later.")
```

### Policy: `min_rust_version_cicd.py`

```python
from packaging.version import Version

with Check("min-rust-version-cicd", "Rust CI/CD version meets minimum") as c:
    rust = c.get_node(".lang.rust")
    if not rust.exists():
        c.skip("Not a Rust project")
        return

    cmds = c.get_node(".lang.rust.cicd.cmds")
    if not cmds.exists():
        c.skip("No Rust CI/CD commands detected")
        return

    min_version = c.input("min_rust_version_cicd", "1.75.0")

    for cmd in cmds:
        version = cmd.get_value(".version")
        if version and Version(version) < Version(min_version):
            c.fail(f"Rust version {version} in CI ('{cmd.get_value('.cmd')}') "
                   f"is below minimum {min_version}.")
            return
```

### Policy: `clippy_clean.py`

```python
with Check("clippy-clean", "Clippy reports no warnings") as c:
    rust = c.get_node(".lang.rust")
    if not rust.exists():
        c.skip("Not a Rust project")
        return

    lint = c.get_node(".lang.rust.lint")
    if not lint.exists():
        c.skip("Clippy data not collected (is the clippy sub-collector enabled?)")
        return

    warnings = c.get_node(".lang.rust.lint.warnings")
    count = len(warnings) if warnings.exists() else 0
    max_warnings = int(c.input("max_clippy_warnings", "0"))

    if count > max_warnings:
        c.fail(f"{count} clippy warning(s) found, maximum allowed is {max_warnings}. "
               f"Run 'cargo clippy' and fix all warnings.")
```

### Policy: `max_unsafe_blocks.py`

```python
with Check("max-unsafe-blocks", "Unsafe block count within limits") as c:
    rust = c.get_node(".lang.rust")
    if not rust.exists():
        c.skip("Not a Rust project")
        return

    unsafe_blocks = c.get_node(".lang.rust.unsafe_blocks")
    if not unsafe_blocks.exists():
        c.skip("Unsafe block data not collected")
        return

    count = c.get_value(".lang.rust.unsafe_blocks.count") or 0
    max_unsafe = int(c.input("max_unsafe_blocks", "0"))

    if count > max_unsafe:
        locations = c.get_node(".lang.rust.unsafe_blocks.locations")
        loc_summary = ""
        if locations.exists():
            locs = [f"{l.get_value('.file')}:{l.get_value('.line')}" for l in locations[:5]]
            loc_summary = f" Found in: {', '.join(locs)}"
            if count > 5:
                loc_summary += f" (and {count - 5} more)"

        c.fail(f"{count} unsafe blocks found, maximum allowed is {max_unsafe}.{loc_summary} "
               f"Reduce unsafe usage or increase the max_unsafe_blocks threshold.")
```

---

## Part 3: Test Environment Setup

### Create a Rust component in pantalasa-cronos

Fork or create a Rust repository in `pantalasa-cronos` for testing:

1. **Option A:** Fork an existing open-source Rust project (e.g., `ripgrep`, `fd`, or a smaller project)
2. **Option B:** Create a minimal Rust project with known characteristics:
   - `Cargo.toml` with edition 2021, some dependencies (serde, tokio)
   - `Cargo.lock` committed
   - A few `unsafe` blocks for testing the policy
   - Some intentional clippy warnings
   - CI workflow with `cargo test` and `cargo clippy`

**Recommended: Option B** — a controlled test project gives predictable results.

```bash
# Create pantalasa-cronos/rust-service
# Structure:
# ├── Cargo.toml         (edition = "2021", rust-version = "1.70.0")
# ├── Cargo.lock
# ├── rust-toolchain.toml (channel = "1.77.0")
# ├── clippy.toml
# ├── src/
# │   ├── main.rs        (application binary)
# │   └── ffi.rs         (2 unsafe blocks for testing)
# └── .github/workflows/ci.yml
```

3. **Add to `lunar-config.yml`:**
```yaml
github.com/pantalasa-cronos/rust-service:
  owner: carlos@pantalasa.org
  domain: engineering.core
  branch: "main"
  tags: [backend, rust, SOC2]
```

4. **Add collector/policy references:**
```yaml
collectors:
  - uses: github://earthly/lunar-lib/collectors/rust@brandon/rust
    on: [rust]

policies:
  - uses: github://earthly/lunar-lib/policies/rust@brandon/rust
    on: [rust]
    enforcement: report-pr
```

### Expected Test Results

```
Expected results (pantalasa-cronos/rust-service):
- cargo-toml-exists      → PASS
- cargo-lock-exists      → PASS (is_application=true)
- min-rust-edition        → PASS (edition=2021, min=2021)
- min-rust-version-cicd   → PASS (version=1.77.0, min=1.75.0)
- clippy-clean            → FAIL (intentional warnings)
- max-unsafe-blocks       → FAIL (2 unsafe blocks, max=0)
```

### Edge Cases to Test

1. **Library crate** — Cargo.toml with only `[lib]`, no `[[bin]]`, no Cargo.lock → `cargo-lock-exists` should SKIP in auto mode
2. **Workspace** — Multi-crate workspace with `[workspace]` and `members` → should detect workspace structure
3. **No rust-toolchain.toml** — Version should fall back to `rustc --version`
4. **No clippy data** — When clippy sub-collector is not included → `clippy-clean` should SKIP
5. **Mixed lib+bin crate** — Both `src/lib.rs` and `src/main.rs` exist → `is_application=true`, `is_library=true`, lockfile required

---

## Part 4: Docker Image

### Earthfile for `earthly/lunar-lib:rust-main`

```Earthfile
VERSION 0.8

rust-base:
    FROM earthly/lunar-lib:base-main
    # Install Rust via rustup (minimal profile)
    RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --default-toolchain stable --profile minimal \
        --component clippy rustfmt
    ENV PATH="/root/.cargo/bin:${PATH}"
    # toml2json for parsing Cargo.toml without Rust compilation
    RUN cargo install toml2json || apk add --no-cache npm && npm install -g @pnpm/toml2json

build:
    FROM +rust-base
    SAVE IMAGE --push earthly/lunar-lib:rust-main
```

Note: The exact Earthfile will depend on the base image and what tools are already available. This is a starting point.

---

## Implementation Order

1. **Spec PR (current):** YAML manifests + READMEs + example Component JSON — get reviewed
2. **After spec approval:**
   a. Create the Rust test component in pantalasa-cronos
   b. Implement `project.sh` first (most foundational)
   c. Implement `dependencies.sh`
   d. Implement `clippy.sh` + Earthfile (needs custom image)
   e. Implement `cicd.sh` and `test-coverage.sh`
   f. Implement all policy Python files
3. **Test locally** with `lunar collector dev` / `lunar policy dev`
4. **Push to demo** and verify end-to-end

---

## Reference

- Existing Go plugin: `collectors/golang/`, `policies/golang/`
- Existing Java plugin: `collectors/java/`, `policies/java/`
- Component JSON conventions: `ai-context/component-json/conventions.md`
- Already-documented Rust paths: `.lang.rust.unsafe_blocks`, `.lang.rust.edition` in `structure.md`
