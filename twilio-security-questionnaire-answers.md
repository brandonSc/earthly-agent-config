# Twilio Security Vendor Assessment — Answers

---

## A. Security Organization and Policies

**A1. Describe your organization's security program.**
Earthly Technologies maintains a security program aligned with SOC 2. The company has completed SOC 2 Type I certification and is currently in the observation period for SOC 2 Type II. The program is managed through Secureframe and includes access controls, endpoint compliance enforcement via Kolide, periodic user access reviews, incident response procedures, tabletop exercises, and quarterly security team meetings. Security policies are reviewed annually and approved by management.

**A2. Is your security program aligned with an industry standard/s?**
Yes — SOC 2 (Type I completed, Type II in progress).

**A3. Is there a dedicated information-security function responsible for security programs?**
Yes. The security function includes the Head of Security and Compliance and the CEO, with active engagement from core engineering. The team is responsible for security policy, incident response, access management, and compliance.

**A4. Has your information security policy been approved by management, communicated to appropriate stakeholders and an owner to maintain, review and enforce the policy(ies)?**
Yes.

**A5. Are all security policies and standards reviewed at least annually?**
Yes.

---

## B. Risk Assessment and Treatment

**B1. Please describe your risk-management framework and program.**
Earthly maintains a risk management program as part of its SOC 2 compliance framework. Risks are identified, assessed, and tracked through Secureframe. The program includes periodic risk assessments, vendor risk reviews, and security incident tracking. Risk treatment decisions are reviewed and approved by management.

**B2. Is your risk-management program approved by management, communicated, managed and enforced by appropriate stakeholders?**
Yes.

---

## C. Asset Management

**C1. Is there an asset-management policy and program?**
Yes. Assets are tracked through Secureframe's asset inventory, which integrates with our cloud providers and SaaS tools.

**C2. Are information assets classified and protected according to their label?**
Yes. Assets are classified and access is controlled based on sensitivity.

**C3. Do you securely dispose of physical assets?**
Yes. Company devices are wiped before disposal or repurposing using industry-standard secure erase methods.

**C4. Is Twilio data and configuration wiped or destroyed when hardware is repurposed?**
Yes. All data is securely wiped before hardware is repurposed or decommissioned.

---

## D. Human Resource Security

**D1. Are security roles and responsibilities defined and documented?**
Yes, in accordance with our information security policy.

**D2. Is background screening performed for all staff who will access Twilio data?**
Yes. Background checks are performed for all employees.

**D3. Have all staff signed confidentiality and privacy agreements?**
Yes, upon hire.

**D4. Do you have a security awareness training program?**
Yes. Security awareness training is provided to all employees.

**D5. Do you have a process to ensure all employees receive training?**
Yes. Training completion is tracked through our compliance platform.

**D6. Do you have a disciplinary process for non-compliance with information security policies?**
Yes. Non-compliance is addressed through our employee handbook and HR processes.

**D7. Do you have a process for termination or change-of-status?**
Yes. Access is revoked across all systems upon termination. User access reviews confirm no residual access for former employees.

**D8. Will your organization process Twilio data in Russia, China, or OFAC-sanctioned jurisdictions?**
No.

---

## E. Physical and Environmental Security

**E1. Will the service be an externally hosted technology/SaaS or installed within Twilio's network?**
Lunar is a self-hosted solution installed within Twilio's own infrastructure. It is not an externally hosted SaaS. All data remains within Twilio's environment.

---

## F. Communications and Security Operations

**F1. Are only approved tools and software used for communication or data storage of Twilio related information?**
Yes. All tools and software are approved through our security review process. Primary tools include GitHub, Google Workspace, Slack, AWS, and 1Password.

**F2. Do you have an anti-virus/malware policy or program?**
Yes. Endpoint compliance is enforced through Kolide, which monitors device health and security posture.

**F2.1 Do workstations and servers have anti-virus/malware installed?**
Yes. Endpoint protection is enforced on all company devices via Kolide.

**F3. Do you have a formal patching and vulnerability management process for network/security devices, workstations, endpoints?**
Yes. Patching is managed through Kolide for endpoints and automated updates for cloud infrastructure. Dependencies are regularly audited and version-pinned.

**F3.1 Do you have a formal patching and vulnerability management process for servers?**
Yes. Server infrastructure runs on AWS managed services (EKS, RDS) which handle OS-level patching. Application-level dependencies are managed through CI/CD pipelines with automated scanning.

**F4. Are system backups of Twilio data and systems performed? What is the interval?**
Lunar is self-hosted within Twilio's infrastructure. While Lunar processes Twilio's data, all data remains in Twilio's environment. Backup scheduling and management is controlled by Twilio within their own infrastructure.

**F4.1 Are backups encrypted?**
Backup encryption is configured by Twilio within their own infrastructure. Lunar supports deployment on encrypted storage and recommends enabling encryption at rest.

**F4.2 If backups are encrypted, what is the encryption strength and how often is the encryption key rotated?**
Backup encryption strength and key rotation are managed by Twilio within their own infrastructure.

**F5. Are firewalls in use for external connections?**
Yes. AWS security groups restrict inbound traffic to only authorized sources. Changes are managed through infrastructure-as-code (Terraform) and require peer review.

**F5.1 Are firewalls in use for internal connections?**
Yes. Internal traffic between services is restricted via AWS security groups. For example, database access is limited to specific EKS node security groups on port 5432 only.

**F6. Describe your process for vulnerability assessments and scans.**
Dependency scanning is performed in CI/CD pipelines. Infrastructure vulnerabilities are monitored through AWS security services. We are currently engaging a third-party penetration testing firm (Cacilian/Prescient Security) for formal assessments.

**F7. Are penetration tests performed by a qualified third party?**
Yes. Cacilian (a Prescient Security company) has been engaged for penetration testing, with testing scheduled for May 2026.

**F8. Describe how you handle configuration management and configuration drift.**
Infrastructure is managed as code using Terraform. All changes require peer review via pull requests with branch protection enforced. This ensures configuration is version-controlled and drift is detectable.

**F9. Are removable media devices prohibited from use?**
Removable media usage is monitored through Kolide endpoint compliance. Policies are enforced to prevent unauthorized data transfer.

**F10. Do you require mobile device management software?**
Endpoint compliance is enforced through Kolide on all devices accessing company resources.

**F11. Please describe your DDoS mitigation strategy.**
Lunar is self-hosted within Twilio's infrastructure, so DDoS mitigation is managed by Twilio as part of their own network security controls. For Earthly's internal infrastructure, AWS Shield Standard provides built-in DDoS protection.

**F12. Is there a data-leakage prevention tool in place?**
Endpoint compliance monitoring is in place via Kolide. Access to sensitive systems requires MFA and is logged.

**F13. Is web-content filtering in place?**
Earthly does not implement web content filtering internally. Since Lunar is self-hosted, web content filtering for the deployed environment is managed by Twilio within their own network controls.

**F14. Are any file integrity monitoring programs used?**
Infrastructure changes are tracked through Terraform state and version control. AWS CloudTrail logs API calls and configuration changes.

**F15. Do you have logging capabilities sufficient to determine root cause of a security incident?**
Yes. Logging is in place across cloud infrastructure (AWS CloudTrail, CloudWatch) and application services.

**F15.1 Are security events logged, reviewed and audited?** Yes.
**F15.2 Are authentication successes and failures logged?** Yes.
**F15.3 Are application errors or system events logged?** Yes.
**F15.4 Are use of system admin privileges logged?** Yes, via AWS CloudTrail.
**F15.5 Are changes to critical files logged?** Yes, via version control and CloudTrail.
**F15.6 Are suspicious or malicious network activity logged?** Yes, via AWS VPC Flow Logs.
**F15.7 Are use of shared or root logons logged?** Yes, via CloudTrail. Root account usage is minimized and monitored.

**F16. Are security logs immutable?**
Yes. AWS CloudTrail logs are stored in S3 with integrity validation enabled.

**F17. Are you always using the most secure versions of SSL/TLS?**
Yes. TLS 1.2+ is enforced on all external connections. Insecure versions are disabled.

**F18. Do you have a Threat Intel function?**
We monitor security advisories and CVE databases for threats affecting our dependencies and infrastructure. This is handled by the security team as part of ongoing operations.

**F19. Do you 'deny' list or 'allow' list communications?**
AWS security groups operate on an allow-list basis. All inbound traffic is denied by default and only explicitly permitted sources/ports are allowed.

**F20. Do you require Twilio to integrate with your service via a custom library?**
No.

**F21. What language is the library written in?**
N/A.

**F22. What version of the library do you use? Are there any known vulnerabilities?**
N/A.

---

## G. Access Control

**G1. Is there a process for the request and approval of new logical access?**
Yes. Access requests are reviewed and approved by management. Access is granted based on role and least-privilege principles.

**G2. Are unique user IDs assigned to specific users for all access?**
Yes. All users have unique accounts. Shared accounts are not permitted (service accounts are documented exceptions).

**G3. Are credentials required to access systems transmitting/processing Twilio data?**
Yes. All systems require authentication. MFA is enforced for AWS, GitHub, and Google Workspace. Passwords must meet complexity requirements enforced through our SSO provider.

**G4. Is remote access permitted? If so, how is it secured?**
Yes. Earthly is a remote-first company. Access is secured through SSO with MFA, VPN where required, and endpoint compliance enforcement via Kolide.

**G5. Are Bastion/Jump hosts and/or VPNs required for remote access?**
Access to production cloud infrastructure requires authenticated access through AWS IAM with MFA. Direct SSH to servers is not standard practice; infrastructure is managed through Kubernetes APIs and infrastructure-as-code.

**G6. Are user reviews performed at least quarterly and documented?**
Yes. User access reviews are performed periodically and documented. The most recent review was completed April 2, 2026.

**G7. Is there a process for access changes due to job transfer or change of duties?**
Yes. Access is reviewed and adjusted when roles change.

**G8. Is there a process for terminating logical access?**
Yes. Upon termination, access is revoked across all systems (AWS, GitHub, Google Workspace, Slack, etc.). Former employee access is verified through periodic access reviews.

**G9. Will vendor personnel ever require access to Twilio's IT environment?**
No. Lunar is self-hosted and does not require Earthly personnel to access Twilio's IT environment. If Twilio requests debugging assistance, support would be provided via screen-sharing sessions only.

---

## H. Information Systems Acquisition Development & Maintenance

**H1. Do you have a formal Secure SDLC process?**
Yes. All code changes go through version-controlled pull requests, peer review, and automated CI/CD testing before deployment. Security considerations are part of the development process.

**H2. Do all changes go through a formal change process?**
Yes. All changes require pull requests with peer review and approval before merging.

**H3. Is there review and approval for all changes related to systems supporting Twilio?**
Yes. Branch protection rules require at least one approval before merging to the main branch.

**H4. Is testing performed for all changes?**
Yes. Automated testing is performed in CI/CD pipelines for all changes.

**H5. Is one central source code repository used?**
Yes. GitHub is used as the central source code repository.

**H6. Is segregation of duties systemically enforced during change deployment?**
Yes. Branch protection rules prevent authors from approving their own changes. An independent reviewer must approve before merge.

**H7. Is there automated secure source code scanning?**
Yes. Dependency scanning and vulnerability checks are integrated into CI/CD pipelines. Runs on every pull request.

**H8. Is source code security peer reviewed before promotion?**
Yes. All code changes require peer review before merging to the main branch.

---

## I. Incident Event and Communications Management

**I1. Do you have formal Security Incident Management procedures?**
Yes. Earthly has a documented incident response plan that includes identification, containment, eradication, recovery, and post-incident review. The team conducts regular tabletop exercises to validate procedures.

**I1.1 Do you have a dedicated Security Incident Response team?**
Yes. The security team, led by the Head of Security and Compliance and the CEO, leads incident response with support from core engineering as needed.

**I2. Does your incident response include timely notification to affected customers?**
Yes. Customer notification is part of our incident response process. Customers are notified promptly of any security or service-impacting incidents.

**I3. Is there an online incident response status portal?**
No. Lunar is self-hosted, so service availability monitoring is managed by Twilio within their own environment. Earthly communicates security advisories directly to customers via email.

**I4. Is there a 24x7x365 staffed phone number to report security incidents?**
Earthly maintains an on-call rotation reachable 24x7 for security incidents. Customers can reach the security team via email or through their designated account contact.

---

## J. Cloud Security

**J1. Are Cloud Services provided?**
No. Lunar is a self-hosted solution deployed within Twilio's own cloud infrastructure. Earthly does not host a multi-tenant cloud service. All data processing occurs within Twilio's environment.

**J2. What cloud hosting provider do you use?**
AWS (Amazon Web Services) for Earthly's internal infrastructure. Lunar is deployed within the customer's own cloud environment.

**J3. Where are the data center(s) located?**
Earthly's internal infrastructure is hosted on AWS in the US West (Oregon) region. Lunar runs in whatever cloud region Twilio chooses for their deployment.

**J4. What is the URL for the admin portal?**
N/A. Lunar is self-hosted within Twilio's infrastructure. There is no Earthly-hosted portal.

**J5. What is the URL for the support portal?**
N/A. Support is provided directly via email and screen-sharing sessions as needed.

**J6. Please list any additional URLs where Twilio must login.**
N/A. Lunar is self-hosted and does not require Twilio to log into any Earthly-hosted services.

**J7. What is the password policy for the admin portal?**
N/A. Authentication is managed within Twilio's own environment.

**J8. Are encryption settings defaulted or does the customer need to configure it?**
Lunar encrypts sensitive data such as secrets used for collector plugins by default. Broader encryption at rest (e.g., database, storage volumes) is configured by Twilio within their own infrastructure.

**J9. Do you support SSO? What protocols (OAuth 2.0, SAML 2.0, etc.)?**
N/A. Lunar is self-hosted and authentication is managed within Twilio's environment.

**J10. Is there a scheduled maintenance window?**
N/A. Lunar is self-hosted. Maintenance and upgrade scheduling is managed by Twilio.

**J11. Do you prevent scheduled maintenance from affecting customers?**
N/A. Lunar is self-hosted. Twilio controls their own maintenance windows.

**J12. Can clients run their own security services within their own cloud environment?**
Yes. Lunar is deployed entirely within the customer's cloud environment, so the customer has full control to run their own security tools and monitoring.

---

## K. Data Security or Cryptography

**K1. Can Twilio define the legal jurisdictions where their data is transmitted/processed/stored?**
Yes. Lunar is self-hosted, so Twilio controls where all data resides within their own infrastructure.

**K2. Is data segmentation and separation between clients provided?**
Yes. Lunar is self-hosted — each customer's deployment is completely isolated. There is no shared infrastructure or multi-tenant data store.

**K3. Is Twilio Data encrypted at rest?**
Yes. Lunar encrypts sensitive data at rest, such as secrets used for collector plugins. The underlying storage encryption (database, volumes) is configured by Twilio within their own infrastructure using their preferred encryption settings.

**K3.1 Is the encryption key periodically rotated?**
Application-level encryption keys are managed within the Lunar deployment. Infrastructure-level key rotation (e.g., AWS KMS) is managed by Twilio within their own environment.

**K4. Are clients provided with the ability to generate a unique encryption key?**
Yes. Since Lunar is self-hosted, customers manage their own encryption keys.

**K5. Are clients provided with the ability to rotate their encryption key?**
Yes. Key rotation is managed by the customer within their own infrastructure.

**K6. Is Twilio data secured while in motion?**
Yes. TLS 1.2+ is enforced for all data in transit.

**K7. Have you had a security/privacy breach in the past 12 months?**
No.

**K8. Is Twilio data securely wiped when hardware is decommissioned?**
Since Lunar is self-hosted, data resides in the customer's infrastructure. Earthly does not have access to customer data or hardware. Secure wiping is the customer's responsibility.

**K9. Are laptops used by employees and contractors encrypted?**
Yes. Full disk encryption is enforced on all company devices, monitored through Kolide.

**K10. Are any special precautions used when transmitting sensitive information?**
Yes. Sensitive data is transmitted only over encrypted channels (TLS 1.2+). Secrets are managed through 1Password and are not transmitted in plaintext.

**K11. Are files too big to email transmitted through alternate secure means?**
Yes. Large files are shared via encrypted, access-controlled channels (e.g., Google Drive with restricted sharing).

---

## L. Third Party Security

**L1. Will third party vendors transmit or store Twilio data?**
No. Lunar is self-hosted within Twilio's infrastructure. No third-party vendors transmit or store Twilio data on Earthly's behalf.

---

## M. Compliance

**M1. Is there an internal audit, risk management or compliance department?**
Yes. Compliance is managed through Secureframe with oversight from the security team. Prescient Assurance serves as the external auditor for SOC 2.

**M2. Is there an internal compliance and ethics reporting mechanism?**
Yes. Employees can report compliance issues through internal channels.

**M3. Do you have an internal whistleblower reporting mechanism?**
Yes. Employees can report issues through internal reporting channels as documented in company policies.

**M4. Is Discovery available for all Twilio data stored?**
Since Lunar is self-hosted, Twilio has full control and access to all data within their own deployment. Earthly does not store Twilio data.

---

## N. Business Continuity and Disaster Recovery

**N1. Is there a documented BC/DR policy approved by management?**
Yes. Earthly has a documented business continuity and disaster recovery policy. BCDR tabletop exercises are conducted periodically.

**N2. Is a Business Impact Analysis conducted at least annually?**
Yes.

**N3. Are full BC/DR tests conducted at least annually?**
Yes. BCDR tabletop exercises are conducted at least annually.

**N4. Are there any disruptions that would be an exception to the maximum RTO?**
No. Since Lunar is self-hosted, customer deployments are not dependent on Earthly's infrastructure availability. Earthly's internal systems (CI/CD, demo environments) have an RTO of 24-48 hours.

**N5. Is there insurance coverage for business interruptions?**
Yes. Earthly maintains business interruption insurance. Details on coverage amounts are available upon request.

---

## O. AI Features

**O1. Are AI/LLM features being provided to Twilio?**
Lunar includes optional Claude-based AI skills that users can choose to enable to assist in authoring collectors or policies. These are opt-in features — Lunar does not run AI within the core product itself. If enabled, AI interactions occur on-demand at the user's discretion.
