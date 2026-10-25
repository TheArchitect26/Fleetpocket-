# Operational integrity remediation

This milestone implements the six priority groups from the [25 October audit](AUDIT-2026-10-25.md). The audit and its read-only probes remain historical evidence, not regression requirements for the repaired implementation.

## Changes

| Audit item | Implemented behavior |
|---|---|
| A01 | Cached jobs pass through browser-time validity handling. Expired ETA values/approval IDs are withheld in overview, drawer, dispatch, messages and paged job details; unknown is never labelled within window. |
| A02 | Approval creates one immutable update in a transaction. Request keys make retry idempotent. Text, interval, vehicle, job version, approver/time and source evidence are bound to the saved version. Copy/Share use that version only and disable on any mismatch or approval expiry. An old response cannot approve changed preview text. |
| A03 | Update cards compare due time with the clock. Monitoring creates a persistent due-update incident, including a missing first update on live work. New approval clears the reminder condition on the next monitor run. There is no automated WhatsApp send. |
| A04 | Conditions have stable identities, versioned incidents, acknowledgement, ownership, resolution notes and occurrence counts. Recovery resolves the condition; subsequent recurrence reopens it without acknowledgement creating duplicates. Monitoring uses valid delivery ETA evidence, distinct documents, driver licence/PrDP dates and missing POD conditions. |
| A08 | Handover/access/summary actions require one explicitly selected customer. Writable vehicle choices respect each tenant's capability. |
| A06, access/export | All records provides scoped server pagination/search, including history outside the overview cache. Paged jobs can advance stages; documents can be previewed, verified/released; incidents can be resolved. Authenticated CSV uses the complete scoped database statement rather than the browser cache. Handovers have their own snapshot window. |

The control-tower map/overview still intentionally holds a bounded 1,000-row collection window and displays a limit warning. Use All records for complete access, and the authenticated CSV for all jobs. Live offset pages can move when concurrent data changes; exports use a single statement snapshot. Very large exports, operational actions beyond those provided in the paged browser and sustained capacity remain further work. No claim is made that every large-fleet interaction or all 18 audit findings is complete.

CSV generation also neutralises leading whitespace/control formula prefixes without discarding the first character. Registered/open-work labels and workload-only badges replace movement/attendance claims. Global monitoring is explicitly denied to anonymous and ordinary authenticated database roles; only the server worker can invoke it.

## Incident rules

Acknowledgement means seen. Take ownership assigns the acting controller. Resolution requires a note. A controller may explicitly resolve an observed condition as an accepted exception; the UI keeps that fact visible and monitoring does not immediately undo the decision. Once that condition clears and genuinely recurs, the same incident reopens with a higher occurrence and cleared resolution state. Audit records retain transitions.

Legacy pre-migration alerts retain their history and can be manually resolved; they have no inferred condition identity. New monitor-generated conditions use the new identities. Run the monitor after migration and review legacy open alerts instead of silently discarding them.

Due-update reminders are evaluated by the existing monitor schedule, documented at five-minute intervals. The browser due badge updates independently. A reminder is an operational queue entry, not a notification-delivery or WhatsApp receipt. Scheduler deployment and external escalation/delivery are still unconfigured.

## Rollout and compatibility

Apply migrations 013–015 in staging after 001–012. Deploy the matching application with the migrations: direct authenticated writes to updates/alerts are revoked. Approval POST now requires job_id and request_key and returns the exact saved snapshot. Incident PATCH now requires a command and expected_version; bare acknowledgement writes are rejected. Existing approved-history rows remain historical evidence; new provenance fields are not fabricated for them.

Approval validity is at most 15 minutes, shortened to a current ETA's earlier expiry when applicable. Editing text/interval, changing vehicle/job or advancing the job invalidates sharing through the current preview. A fresh GPS sample alone does not rewrite the immutable approved message.

Records/export RPCs execute with caller RLS. Arbitrary table names are never accepted; collections are allowlisted. Customer users still cannot read unreleased documents or raw operational audit history. Monitor condition evaluation remains server-only and serialised to avoid overlapping reconciliation.

## Verification scope

New tests target cached expiry, delayed approval responses with editing, interval/job mismatch, approval expiry, due-time boundaries, immutable database approval, incident recovery/recurrence and permission checks, explicit customer selection, 1,105 records beyond the old cap, complete export and preserved handovers. CI is the source of full pass/fail evidence; do not infer a pass from this test inventory. The initial expanded database run passed; complete application/browser verification is being iterated before delivery.

Remaining audit work includes native providers, hosting/schedules, recovery/backup/monitoring setup, finer document/identity workflows, fleet editing and reassignment, historical SLA reporting, independent accessibility/security review and sustained multi-worker load acceptance.
