# Meridian Demo Performance Test Report

**Test date:** February 19, 2026
**Test period:** 16:16 – 17:05 (local time)
**Environment:** meridian.demo.earthly.dev
**Baseline (idle):** Components listing ~2.2s, Home page ~2.2s
**Method:** Push a commit to each component (sequentially, excluding backend), measure page load times at 45s and 2min marks

---

## Page Load Times by Component

All times in seconds. Baseline is ~2.2s for both pages when system is idle.

| # | Component | Lang | 45s: Components | 45s: Home | 2min: Components | 2min: Home | Severity |
|---|-----------|------|-----------------|-----------|-----------------|------------|----------|
| 1 | **frontend** | Node | 3.6 | 2.7 | 2.2 | 2.2 | ✅ Normal |
| 2 | **auth** | Python | 3.6 | 2.7 | 2.2 | 2.2 | ✅ Normal |
| 3 | **spring-petclinic** | Java | 2.7 | 5.7 | 4.7 | 7.3 | ⚠️ Slow |
| 4 | **inventory** | Java | 5.3 | 9.3 | 5.3 | 10.8 | 🔴 Very slow |
| 5 | **hadoop** | Java | 6.9 | 13.6 | 5.3 | 10.6 | 🔴 Very slow |
| 6 | **spark** | Java | 11.1 | 13.8 | 7.6 | 11.3 | 🔴 Very slow |
| 7 | **ctlstore** | Go | 6.4 | 15.4 | 8.5 | 13.2 | 🔴 Very slow |
| 8 | **kubeflow-manifests** | k8s | 7.8 | 16.7 | 6.8 | 14.0 | 🔴 Very slow |
| 9 | **prometheus-helm-charts** | Helm | 5.2 | 9.7 | 5.3 | 10.6 | 🔴 Slow |
| 10 | **DataProfiler** | Python | 10.0 | 20.8 | 6.8 | 13.8 | 🔴🔴 Extremely slow |
| 11 | **datacompy** | Python | 17.2 | 22.9 | 12.9 | 27.7 | 🔴🔴🔴 Nearly unresponsive |
| 12 | **react-native-pathjs-charts** | Node | 23.2 | 25.8 | — | — | 🔴🔴🔴 Nearly unresponsive |
| 13-15 | **cqrs + fpe + checks-out** | Java/Go | 34.3 | 41.5 | 19.9 | 32.2 | 🔴🔴🔴🔴 System overwhelmed |
| — | **Recovery (+5 min)** | — | 19.9 | 32.2 | — | — | Still 9-14x baseline |
| — | **Recovery (+10 min)** | — | 15.9 | 26.2 | — | — | Still 7-12x baseline |

---

## Key Findings

### 1. The slowdown is cumulative and systemic, not per-component

The system doesn't recover between component pushes. Each push stacks collector/policy runs, and the DB (PostgreSQL) and hub get progressively overwhelmed. The first two components (frontend, auth) were fine in isolation.

### 2. The system takes >10 minutes to recover

Even after all pushes stop, at 10 minutes after the last push pages were still 7-12x baseline. The system never returned to idle performance during the test window.

### 3. The Home page is consistently the slowest dashboard

It runs more SQL queries (company overview, initiatives, domains) so it's the first to feel DB pressure. Components listing is about half as slow.

### 4. No single component is the culprit

The degradation pattern shows:
- **Components 1-2** (frontend, auth): ✅ No impact when system is idle
- **Components 3-6** (spring-petclinic through spark): ⚠️ Noticeable degradation as collectors stack up
- **Components 7+** (ctlstore onward): 🔴 System already saturated, every additional component makes it worse

### 5. Java repos are heavier but it's not Java-specific

Java repos have more collectors (syft SBOM generation on large dependency trees is expensive), and `hadoop` (168 vulnerabilities) and `spark` (8 vulns) are particularly large. But the issue is about total system load, not any one language.

---

## Other Observations

- **GitHub vulnerability warnings during push:**
  - hadoop: 168 vulnerabilities (13 critical, 71 high, 64 moderate, 20 low)
  - spark: 8 vulnerabilities (1 critical, 2 high, 5 moderate)
  - spring-petclinic: 1 critical vulnerability
  - ctlstore: 3 moderate vulnerabilities
- **Check counts fluctuate during runs:** e.g. frontend went from 30/60 → 15/30 → 24/56 as collectors re-ran and policies re-evaluated
- **Total checks dropped from 897 → 730 → 776 → 793** as components were mid-evaluation simultaneously
- **The "Passing checks" numbers on the Home page are live** — they shift as collectors/policies complete, which means during heavy load the UI shows inconsistent/stale data

---

## Root Cause Assessment

The bottleneck is likely **concurrent collector/policy Docker containers + DB writes/reads**. Each component push triggers ~20+ collectors (code collectors) and ~20+ policies, each running as a Docker container. When 5+ components are being processed simultaneously, the single EC2 instance is overwhelmed (CPU, memory, I/O, and PostgreSQL connections).

### Potential mitigations to investigate

1. **Collector concurrency limits** — cap how many collectors/policies run in parallel per component or globally
2. **Queue-based processing** — serialize collector runs instead of running all at once
3. **Grafana query optimization** — the Home dashboard SQL queries may need optimization (indexes, materialized views) to stay fast under write-heavy load
4. **Resource scaling** — larger EC2 instance or separate DB instance
5. **Prioritized scheduling** — run lightweight collectors first, defer heavy ones (syft, semgrep) to avoid blocking the system
