# Fleet Pocket documentation

Start with [what Fleet Pocket does](../README.md). These documents describe the current implementation, its operating limits and the next work.

## Using and evaluating the app

| Document | Audience and purpose |
|---|---|
| [User guide](USER_GUIDE.md) | Controllers and customer users: fleet scope, dispatch, documents, updates and reports. |
| [Operations guide](OPERATIONS.md) | MCY administrators and supervisors: access, handovers, failure handling and pilot responsibilities. |
| [Testing guide](TESTING.md) | Testers: local startup, fictional accounts, supported scenarios and bug reports. |
| [Current status](STATUS.md) | Product owners: implemented features, limitations and verified test evidence. |
| [Latest audit](AUDIT-2026-10-25.md) | Product and engineering: findings, evidence, severity and acceptance checks. |
| [Roadmap](ROADMAP.md) | Delivery planning: ordered work and release gates. |

## Technical reference

- [Architecture](ARCHITECTURE.md): application boundaries, tenancy, data and integrations.
- [Deployment](DEPLOYMENT.md): environment variables, migrations, hosting, schedules and recovery requirements.
- [Second remediation](SECOND-REMEDIATION.md): current ETA publication/queue policy and migrations 010–012.
- [First remediation](REMEDIATION.md): historical implementation and migrations 006–009; later policy changes supersede its original publication rule.

## Historical audit evidence

[23 October audit](AUDIT-2026-10-23.md) and [24 October audit](AUDIT-2026-10-24.md) remain historical records. Their finding lists and test totals do not describe the latest state. The [25 October audit](AUDIT-2026-10-25.md) reassesses the current application and links executable read-only probes.

Product descriptions should identify what people can do, distinguish implemented behavior from planned capability, and link technical instructions rather than embedding them in the main product README. Test results must name their tested commit/run. Passing automated checks does not establish live-provider, security, accessibility or capacity acceptance.
