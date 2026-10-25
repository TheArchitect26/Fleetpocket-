Implementation follow-up: [operational integrity remediation](THIRD-REMEDIATION.md) implements milestone 1 and complete record access/export. Remaining overview/scale and deployment limits are stated there; the original planning sequence follows.

# What comes next

Fleet Pocket can enter controlled fictional-data UAT now using [the testing handover](TESTING.md). The next engineering milestone should make the operational information and approvals dependable before adding more modules. Priorities reference the [25 October audit](AUDIT-2026-10-25.md).

## 1. Fix operational truth and approval integrity

Suggested owner: application lead, with MCY operations deciding wording and thresholds.

| Work | Completion evidence |
|---|---|
| Expire ETA consistently in table, drawer, dispatch, map context and sharing (A01). | Browser clock/failed-refresh tests prove an expired forecast is unavailable and never Within delivery window. |
| Bind approval to the exact saved update version and interval; prevent in-flight edit races and approved-record mutation (A02). | Delayed approval + editing test; stored version/hash/approver/time; only that version can be copied/shared through the workflow. |
| Compute due/overdue updates and create a reminder work queue without automatic sending (A03). | All preset/custom intervals, time boundaries, retry/deduplication and approval-before-share tests. |
| Reconcile alert conditions and add owner, resolution and recurrence semantics (A04). | Stale GPS recovery, expired ETA, repeated acknowledgement, multiple document expiries and missing POD scenarios. |
| Require one explicit customer for handovers, access changes and summaries (A08). | A combined workspace cannot silently act on its first tenant; mixed-role tests confirm correct controls and API denials. |

This is the recommended next implementation batch. Do not describe these findings as fixed until the behavior and regression tests pass.

## 2. Provide a usable supervised UAT environment

Suggested owner: deployment operator and MCY test lead. This can proceed alongside milestone 1 using fictional data.

Provide an HTTPS test URL, dedicated database/storage, test accounts for staff and customer roles, reproducible fictional data, worker/monitor schedules, safe secrets and visible integration/test status. Record the tested version and give testers the user guide and bug-report instructions. Keep live providers disconnected during this stage.

Exit: named MCY testers complete the delivery/POD/update/exception/permission checklist, issues are triaged by severity, and session expiry, mobile/keyboard use and service outages have recorded results. A successful local CI run alone is not this acceptance.

## 3. Complete daily operating and scale controls

Suggested owners: application/data leads and MCY supervisor.

Add server-side pagination and complete exports; separate operational events/handovers from telemetry audit volume (A06). Correct counts/shift labels (A07), fleet/driver/job reassignment and editing (A10/A12), document lifecycle/driver expiry/scanning/reconciliation (A09), consistent API failures and protected entry points (A11/A15), and stronger CSV export handling (A14).

Exercise more than 1,000 records, two concurrent workers, multiple controllers and mixed tenant roles. Measure queue age, route calls, rate limits and degraded-operation behavior. Agree fleet size and feed cadence before setting a capacity target. Test actual backups of database and files, then restore both.

## 4. Connect one authorised tracking provider for a bounded pilot

Suggested owner: integration lead with the transport customer's provider administrator.

Obtain documented provider authentication/signature and vehicle mapping. Add per-connection secrets and health, test fixture/native payload compatibility, delayed/duplicate/out-of-order readings, outages and recovery. Use contracted/self-hosted routing capacity. Agree ETA policy and escalation contacts with MCY. Establish observability, retention and rollback evidence (A05/A13/A18).

Exit: the nominated customer's authorised fleet passes real-provider acceptance, independent security/privacy review and operational readiness review. Increase fleet size only after sustained load evidence supports it. No estimate may be labelled as a confirmed GPS position.

## 5. Expand after the pilot is stable

Develop richer customer onboarding, historical SLA reports, evaluated AI event interpretation, structured handovers and deeper dispatch tooling. Add a versioned mobile API/token contract before Android delivery. Automated messaging requires a separate consent, template, approval and delivery-status design; a saved interval is not sufficient.

## Decisions MCY must make

Confirm the pilot customer and fleet size, GPS cadence, what constitutes a material ETA change, who can review/share updates, reminder/escalation ownership, customer-visible driver/contact/document information, exception/cargo-recovery rules, and retention/recovery objectives. Existing implementation defaults support testing; they are not evidence of MCY operational acceptance.
