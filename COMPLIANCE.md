# Compliance & Security — Agent Reference

Notes from the SOC 2 / security compliance work session (April–May 2026). Future agents should reference this when working on compliance tasks, vendor questionnaires, or security documentation.

---

## Compliance Repo

**Location**: `github.com/earthly/compliance` (private)
**Local clone**: `/tmp/compliance-repo` (may need to re-clone)

This is the **source of truth** for all compliance documents. It contains:

```
├── policies/               # All security policies (source of truth, edit here first)
├── incidents/               # Security incident reports (YYYY/YYYY-MM-description/)
├── tabletop-exercises/      # Security + BCDR tabletop exercises (YYYY/)
├── access-reviews/          # Quarterly user access reviews (YYYY/YYYY-MM/)
├── security-meetings/       # Quarterly security team meeting notes (YYYY/YYYY-QN.md)
├── vendor-questionnaires/   # Completed vendor questionnaires (YYYY/vendor-name/)
├── evidence/                # SOC 2 evidence statements
├── templates/               # Reusable templates (post-incident report, etc.)
├── diagrams/                # Architecture diagrams (lunar-architecture.png)
├── scripts/                 # export-pdf.sh, export-all-policies.sh
├── assets/                  # Earthly logo, LaTeX template for branded PDFs
└── soc2/                    # SOC 2 audit tracking
```

### Branded PDF Export

Any markdown in the compliance repo can be exported to a branded PDF with the Earthly logo:

```bash
cd <compliance-repo>
./scripts/export-pdf.sh policies/some-policy.md ~/Desktop/output.pdf
./scripts/export-all-policies.sh ~/Desktop/policies  # bulk export
```

Prerequisites: `brew install pandoc basictex` then `sudo tlmgr install titlesec parskip fancyhdr helvetic`

### Policy Workflow

1. Edit policies in `policies/` (source of truth)
2. Export to branded PDF via `export-pdf.sh`
3. Sync changes to Secureframe
4. Share PDFs with vendors as needed

---

## SOC 2 Status

- **SOC 2 Type I**: Completed
- **SOC 2 Type II**: Observation period in progress (ends ~June 15, 2026). Report expected 4-8 weeks after.
- **Compliance platform**: Secureframe (app.secureframe.com)
- **External auditor**: Prescient Assurance
- **Penetration testing**: Cacilian (a Prescient Security company), pentest@cacilian.com
- **Endpoint compliance**: Kolide

---

## Key Architectural Points for Questionnaires

When answering security questionnaires or drafting compliance docs:

- **Lunar is self-hosted** in customer environments. Earthly does not run a SaaS or hosted production environment.
- Many infrastructure questions (backups, DDoS, maintenance windows, encryption at rest, firewalls) **defer to the customer** since they control their own environment.
- There is **no shared infrastructure** between customers. Each deployment is completely isolated.
- There is **no path from a customer deployment back to Earthly**.
- Earthly's internal AWS infrastructure (us-west-2) is for development, CI/CD, and demo/POV environments only.
- **AI features are optional and opt-in**. Lunar does not host AI models. Customers configure their own LLM provider. Earthly does not collect or transmit data to AI systems on the customer's behalf.

---

## Security Team

- Head of Security and Compliance: Brandon Schurman
- CEO: Vlad Ionescu
- Core engineering actively engaged
- In external-facing documents, use titles not names (e.g., "Head of Security and Compliance" not "Brandon")

---

## Secureframe Tips

- **Tests page**: Compliance > Tests. Filter by status. "Last uploaded" and "Next due date" are useful for finding stale evidence.
- **Disabled/unmapped tests**: If not mapped to your active SOC 2 framework, they're out of scope — ignore them.
- **Personnel page**: Governance > Personnel. 8 active personnel. Outside collaborators from open source repos show up in vendor exports but not in Personnel.
- **Unlinked accounts**: Personnel > Unlinked accounts. Service accounts can use placeholder emails (e.g., service-ci-cd@earthly.dev) and be marked as non-personnel.
- **Evidence uploads**: Many tests just need a screenshot or PDF. Use the answer doc or compliance repo for reference.

---

## Vendor Questionnaires

The Twilio questionnaire (104 questions, 15 sections) was completed in May 2026 and is the template for future vendor questionnaires. Answers are in:
- `vendor-questionnaires/2026/twilio/questionnaire.md` (in compliance repo)
- `twilio-security-questionnaire-answers.md` (in this repo)

Key patterns:
- Most infrastructure questions answered with "Lunar is self-hosted, managed by the customer"
- AI questions answered with "customer configures their own LLM provider, Earthly doesn't host models"
- Don't overstate capabilities. Keep answers concise and factual.
- Don't mention specific team member names in external docs — use titles.
- Don't volunteer exact dates for things like BCDR exercises — say "periodically" or "at least annually"

---

## Recurring Activities & Due Dates

| Activity | Frequency | Next Due |
|---|---|---|
| User access review | Quarterly | July 2026 |
| Security team meeting | Quarterly | August 2026 |
| Security tabletop exercise | Annually | April 2027 |
| BCDR tabletop exercise | Annually | May 2027 |
| Penetration test | Annually | May 2026 (scheduled with Cacilian) |
| Policy review | Annually | As needed |
| Performance reviews | Annually | As needed |

---

## Documents Created in This Session

| Document | Location |
|---|---|
| Security incident report (Trivy CVE-2026-33634) | compliance repo: `incidents/2026/2026-03-trivy-supply-chain/` |
| Security tabletop exercise | compliance repo: `tabletop-exercises/2026/2026-04-security-incident-response/` |
| BCDR tabletop exercise | compliance repo: `tabletop-exercises/2026/2026-05-bcdr/` |
| User access review | compliance repo: `access-reviews/2026/2026-04/` |
| Security team meeting (Q2 2026) | compliance repo: `security-meetings/2026/2026-Q2.md` |
| Twilio questionnaire answers | compliance repo + this repo |
| Post-incident report template | compliance repo: `templates/post-incident-report.md` |
| Environment segregation statement | compliance repo: `evidence/environment-segregation/` |
| AI Security Policy | compliance repo: `policies/ai-security-policy.md` |
| 19 Secureframe policies (converted to markdown) | compliance repo: `policies/` |
| Lunar architecture diagram | compliance repo: `diagrams/lunar-architecture.png` |
| SOC 2 todo list | compliance repo: `soc2/todo.md` |

---

## Open Items (as of May 2026)

- [ ] Kolide password policy enforcement
- [ ] Annual performance reviews
- [ ] Penetration test (scheduled with Cacilian, ~May 18)
- [ ] Finish remaining Secureframe tests needing evidence upload
- [ ] User access review follow-ups (localdev account 2FA, ci-cd account possibly unused, littleredcorvette bot account)
- [ ] Lindsay Kunz suspended Google account — remove admin role
- [ ] 2FA enforcement on Slack/Google for some team members (confirm if SSO covers)
