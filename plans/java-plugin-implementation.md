# Java Plugin Implementation Plan

## Overview

Port the Java language collector and create a Java policy for lunar-lib. Modeled after the Go collector (`lunar-lib/collectors/golang/`) which is the reference implementation.

Java is the most complex language plugin because it has two major build systems (Maven and Gradle) with different tooling, version detection, and dependency resolution.

**Prototype location:** `pantalasa-cronos/lunar/collectors/java/`

**Important:** The Go collector's CI sub-collectors use `jq` in native mode. This is an existing inconsistency with the updated guide. New language CI sub-collectors should follow the updated guide: **native-bash, no `jq`, use `lunar collect` with individual fields.**

---

## Collector: `java`

Directory: `lunar-lib/collectors/java/`

### Sub-collectors

| Sub-collector | Hook | Image | Description |
|---------------|------|-------|-------------|
| `project` | `code` | `base-main` | Detect Java project structure, build tool, Java version from config |
| `dependencies` | `code` | `base-main` | Parse `pom.xml` or `gradle.lockfile` for dependencies |
| `java-cicd` | `ci-before-command` | `native` | Record java/javac commands in CI |
| `maven-cicd` | `ci-before-command` | `native` | Record Maven commands, detect Maven version |
| `gradle-cicd` | `ci-before-command` | `native` | Record Gradle commands, detect Gradle version |
| `test-scope` | `ci-before-command` | `native` | Detect if tests run all modules or specific ones |
| `test-coverage` | `ci-after-command` | `native` | Extract JaCoCo coverage after test runs |

### Component JSON Paths

All data writes to `.lang.java.*`:

| Path | Type | Sub-collector | Description |
|------|------|--------------|-------------|
| `.lang.java.version` | string | project | Java version from build config (e.g. `"17"`) |
| `.lang.java.build_systems` | array | project | `["maven"]`, `["gradle"]`, `["maven", "gradle"]` |
| `.lang.java.source` | object | project | `{tool: "java", integration: "code"}` |
| `.lang.java.native.pom_xml` | object | project | `{exists: true/false}` |
| `.lang.java.native.build_gradle` | object | project | `{exists: true/false}` |
| `.lang.java.native.gradlew` | object | project | `{exists: true/false}` |
| `.lang.java.native.mvnw` | object | project | `{exists: true/false}` |
| `.lang.java.native.gradle_lockfile` | object | project | `{exists: true/false}` |
| `.lang.java.native.checkstyle_configured` | boolean | project | Checkstyle config detected |
| `.lang.java.native.spotbugs_configured` | boolean | project | SpotBugs config detected |
| `.lang.java.dependencies.direct[]` | array | dependencies | `{path: "group:artifact", version, indirect: false}` |
| `.lang.java.dependencies.transitive[]` | array | dependencies | (empty for now) |
| `.lang.java.dependencies.source` | object | dependencies | `{tool: "maven"/"gradle", integration: "code"}` |
| `.lang.java.native.java.cicd.cmds[]` | array | java-cicd | `{cmd, version}` |
| `.lang.java.native.maven.cicd.cmds[]` | array | maven-cicd | `{cmd, version}` |
| `.lang.java.native.gradle.cicd.cmds[]` | array | gradle-cicd | `{cmd, version}` |
| `.lang.java.cicd.source` | object | all cicd | `{tool: "java", integration: "ci"}` |
| `.lang.java.tests.scope` | string | test-scope | `"all"` or `"module"` |
| `.lang.java.tests.coverage` | object | test-coverage | `{percentage, source: {tool: "jacoco", integration: "ci"}}` |
| `.testing.coverage` | object | test-coverage | Normalized coverage (dual-write) |
| `.testing.source` | object | test-scope | `{tool: "maven-surefire"/"gradle-test", integration: "ci"}` |

### Key Implementation Notes

**`project.sh` (code hook):**
- Detect via `*.java` files, `pom.xml`, `build.gradle`, `build.gradle.kts`
- Use `helpers.sh` with an `is_java_project` function
- Detect build systems: maven (pom.xml), gradle (build.gradle/build.gradle.kts/gradlew)
- Detect wrapper existence: `mvnw`, `gradlew`
- Extract Java version **statically from build config** (not from runtime):
  - Maven: `<java.version>` or `<maven.compiler.source>` in pom.xml
  - Gradle: `sourceCompatibility` or `JavaVersion.VERSION_XX` in build.gradle
- Detect static analysis tools: Checkstyle (`checkstyle.xml`, `checkstyle` plugin in build config), SpotBugs (spotbugs plugin)
- Write to `.lang.java` — MUST be written for policy detection
- Use `categories: ["languages", "build"]` in landing page (matching Go collector)

**`dependencies.sh` (code hook):**
- Maven: Parse `pom.xml` using Python's `xml.etree.ElementTree` (available in base image)
  - Resolve property references like `${junit.version}` from `<properties>`
  - Format: `{path: "groupId:artifactId", version: "..."}`
- Gradle: Parse `gradle.lockfile` if present (simpler line-by-line format)
- Write to `.lang.java.dependencies`

**CI sub-collectors (all `native`):**
- `java-cicd`: Pattern `.*\b(java|javac)\b.*` — record Java runtime version
- `maven-cicd`: Pattern `.*\b(mvn|mvnw)\b.*` — detect Maven version (path extraction, wrapper props, or `mvn --version`)
- `gradle-cicd`: Pattern `.*\b(gradle|gradlew)\b.*` — detect Gradle version
- **ALL MUST be native-bash** — no `jq`. Use `lunar collect` with individual fields.
- The prototype's Maven CI collector has thorough version detection (4 methods) — port the logic but rewrite without `jq`

**`test-scope.sh` (ci-before-command, `native`):**
- Pattern: `.*\b(mvn|mvnw|gradle|gradlew)\b.*test.*`
- Check for `-pl`/`-projects` (Maven module selection) or `--tests` (Gradle)
- Write `"all"` or `"module"` scope to `.lang.java.tests.scope`
- Also write `.testing.source` to signal tests executed (dual-write pattern)

**`test-coverage.sh` (ci-after-command, `native`):**
- Pattern: `.*\b(mvn|mvnw|gradle|gradlew)\b.*test.*`
- Look for JaCoCo XML report in standard locations:
  - Maven: `target/site/jacoco/jacoco.xml`
  - Gradle: `build/reports/jacoco/test/jacocoTestReport.xml`
- Extract coverage using native grep/awk from JaCoCo XML (look for `<counter type="LINE"` elements, extract `missed` and `covered` attributes, calculate percentage)
- If native XML parsing is too fragile, this sub-collector can exceptionally use `base-main` image for Python XML parsing access
- Write to BOTH `.lang.java.tests.coverage` AND `.testing.coverage` (dual-write)

### Files

| File | Purpose |
|------|---------|
| `lunar-collector.yml` | Manifest with all 7 sub-collectors |
| `project.sh` | Project detection (code hook) |
| `dependencies.sh` | Dependency parsing (code hook, uses Python for XML) |
| `java-cicd.sh` | Java command recording (native) |
| `maven-cicd.sh` | Maven command recording (native) |
| `gradle-cicd.sh` | Gradle command recording (native) |
| `test-scope.sh` | Test scope detection (native) |
| `test-coverage.sh` | JaCoCo coverage extraction (native or base-main) |
| `helpers.sh` | `is_java_project` function |
| `README.md` | Documentation |
| `assets/java.svg` | Icon |

### Differences from Prototype

1. **CI collectors use `jq`** — must be rewritten as native-bash
2. **CI collectors use container image** — should be `native`
3. **`install.sh` exists** — remove
4. **`test-coverage.sh` uses embedded Python** — may need to keep Python for XML parsing, but use container image exception
5. **No `source` metadata** — add consistently
6. **Maven CI collector has verbose debug logging** — clean up excess `echo` lines
7. **Missing wrapper detection** — add `mvnw`/`gradlew` existence
8. **Missing static analysis tool detection** — add Checkstyle, SpotBugs config
9. **No dual-write to `.testing`** — test-scope and test-coverage must write to both paths

---

## Policy: `java`

Directory: `lunar-lib/policies/java/`

### Checks

| Check | What it does | Input |
|-------|-------------|-------|
| `wrapper-exists` | Ensures build tool wrapper exists (`mvnw` or `gradlew`) | — |
| `min-java-version` | Ensures Java version from build config meets minimum | `min_java_version` (default `"17"`) |
| `min-maven-version` | Ensures Maven version in CI meets minimum | `min_maven_version` (default `"3.9.0"`) |
| `min-gradle-version` | Ensures Gradle version in CI meets minimum | `min_gradle_version` (default `"8.0.0"`) |
| `tests-all-modules` | Ensures tests run across all modules (not just a subset) | — |

### Policy Implementation Notes

- All checks should verify `.lang.java` exists first, skip if not a Java project
- `wrapper-exists`: Check `.lang.java.native.mvnw.exists` (for Maven projects) or `.lang.java.native.gradlew.exists` (for Gradle projects). Skip if build system not detected.
- `min-java-version`: Compare `.lang.java.version` against threshold. Java versions are major numbers (`"17"`, `"21"`) — use integer comparison.
- `min-maven-version`: Check `.lang.java.native.maven.cicd.cmds[].version` — skip if no Maven CI data
- `min-gradle-version`: Check `.lang.java.native.gradle.cicd.cmds[].version` — skip if no Gradle CI data
- `tests-all-modules`: Check `.lang.java.tests.scope == "all"` — skip if no test data

---

## Implementation Steps

1. Create worktree `lunar-lib-wt-java` on branch `brandon/java`
2. Read `lunar-lib/collectors/golang/` as the reference
3. Implement the `java` collector (7 sub-collectors)
4. Implement the `java` policy (5 checks)
5. Test using `lunar dev` commands against pantalasa-cronos components
6. Complete the pre-push checklist
7. Create draft PR

---

## Testing

### Local Dev Testing

```yaml
# In pantalasa-cronos/lunar/lunar-config.yml
collectors:
  - uses: ../lunar-lib-wt-java/collectors/java
    on: ["domain:engineering"]

policies:
  - uses: ../lunar-lib-wt-java/policies/java
    name: java
    initiative: good-practices
    enforcement: report-pr
    with:
      min_java_version: "17"
      min_maven_version: "3.9.0"
      min_gradle_version: "8.0.0"
```

```bash
# Collector (code hooks — test on multiple components)
lunar collector dev java.project --component github.com/pantalasa-cronos/hadoop
lunar collector dev java.project --component github.com/pantalasa-cronos/spark
lunar collector dev java.project --component github.com/pantalasa-cronos/backend
lunar collector dev java.dependencies --component github.com/pantalasa-cronos/hadoop
lunar collector dev java.dependencies --component github.com/pantalasa-cronos/spark

# Policy
lunar policy dev java.wrapper-exists --component github.com/pantalasa-cronos/hadoop
lunar policy dev java.min-java-version --component github.com/pantalasa-cronos/hadoop
lunar policy dev java.min-java-version --component github.com/pantalasa-cronos/backend
lunar policy dev java.min-maven-version --component github.com/pantalasa-cronos/hadoop
```

### Expected Results (pantalasa-cronos)

| Component | project | dependencies | wrapper-exists | min-java-version | min-maven/gradle-version |
|-----------|---------|-------------|---------------|-----------------|------------------------|
| hadoop (Java) | PASS | PASS (has pom.xml or gradle) | Verify mvnw/gradlew | Verify version >= 17 | Verify build tool version |
| spark (Java) | PASS | PASS | Verify | Verify | Verify |
| backend (Go) | exits cleanly | exits cleanly | SKIP (not Java) | SKIP | SKIP |
| frontend (Node) | exits cleanly | exits cleanly | SKIP (not Java) | SKIP | SKIP |

*These are draft expected results — verify and adjust before handing off.*

### Edge Cases to Test

1. **Component with no Java files** — Collector exits cleanly, all policies skip
2. **Maven project with property-referenced versions** (e.g. `${spring.version}`) — `dependencies.sh` should resolve from `<properties>` section
3. **Gradle project without lockfile** — `dependencies.sh` exits cleanly (can't parse deps without lockfile or build tool)
4. **Project with both pom.xml and build.gradle** — `build_systems` should contain both `["maven", "gradle"]`
5. **Java version in different formats** — `<java.version>17</java.version>` vs `<maven.compiler.source>17</maven.compiler.source>` vs `JavaVersion.VERSION_17` — all should be detected
6. **Project without wrapper** — `wrapper-exists` should FAIL for the relevant build system
