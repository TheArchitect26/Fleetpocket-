# MCY administration and operating guide

Fleet Pocket is a controlled testing candidate. This guide establishes responsibilities for evaluating it and preparing a pilot; it does not claim that hosting, tracking contracts, backup or monitoring services already exist.

## Access and onboarding

An administrator provisions the account and assigns memberships to specific transport companies. Public signup is disabled in the local configuration; confirm the same setting in any hosted project. No staff role automatically grants every company's data.

| Role | Current permissions within an authorised company |
|---|---|
| MCY administrator | Operational control and customer-role membership management. |
| Controller | Fleet creation, dispatch, verification/release, ETA/update approval, incident ownership/resolution and handovers. |
| Customer administrator | Job submission, document uploads, own-upload visibility, released documents/reviewed ETAs and customer-role membership management. |
| Customer viewer | Read permitted fleet/job records, reviewed ETAs and released eligible documents. |

Customer administrators cannot grant staff roles or change their own membership through Team & access. Identities must already exist. Tenant creation, invitations, password recovery and staff membership changes require administrator intervention outside the current app. Driver contact details are currently visible to authorised tenant readers; agree the intended customer privacy policy before inviting real users.

Record which MCY person owns each customer and who handles after-hours exceptions. Use named accounts rather than shared credentials. The application does not currently prove that a displayed controller is on duty, or enforce an MFA enrollment workflow.

## Start of shift

Check sign-in, selected customer, last successful sync, active work, stale GPS, delivery windows, POD follow-ups and outstanding exceptions. Confirm tracking status with the provider/operations team; the current integrations screen is configuration guidance, not a per-provider health console. Check document expiry records and driver licence/PrDP dates separately: automated monitoring does not cover every driver date.

An assigned job records the acting controller. There is no workload-based reassignment or attendance system. Do not treat On shift badges as an attendance record.

## Failures and fallbacks

| Situation | Controller response | Administrator responsibility |
|---|---|---|
| No or stale GPS | Contact the driver through the agreed channel; describe location as unconfirmed until a real reading arrives. | Check the correct vehicle/provider connection and webhook processing. Never insert an estimated location as GPS. |
| Routing unavailable | Use the existing reviewed estimate only while valid, identifying its source/time; otherwise communicate ETA unavailable. | Inspect queue age, retries and provider errors; restore routing before depending on automated estimates. |
| Failed ETA work | Select the customer and inspect ETA processing on Incidents. Retry only with an active job and recent confirmed GPS. | Distinguish historical failed work from an unresolved current failure. Terminal-history cleanup/reconciliation is unfinished. |
| Workspace refresh fails | Read the last-sync warning, refresh and verify critical values before acting. | Investigate Auth/API/network health. A successful mutation may already be saved. |
| Session expires | Sign in again; protect the workstation. | Review revocation/expiry behavior. The current UI can retain its last in-memory snapshot after a 401. |
| Upload metadata fails | Record the request reference and escalate; do not mark a missing file verified. | Reconcile private orphan files and metadata. There is no automated orphan-recovery console yet. |
| WhatsApp unavailable | Use an approved alternative communication channel and record what was communicated. | Do not label Copy/Share as proof of sending or delivery. |
| AI unavailable | Use the explicitly labelled rules summary and original records. | Restore the optional provider if required. AI currently summarises alert counts, not individual causes. |
| Map tiles fail | Use the fleet table and confirmed-coordinate details. | Review map service availability and terms; map availability is separate from GPS ingestion. |

## End of shift

Select one customer before writing a handover. Record outstanding jobs, missing PODs, exceptions, people to contact, latest confirmed information and next actions. Confirm incoming coverage outside the app. Acknowledging an alert does not resolve it. Use Take ownership and Record resolution for incidents; a handover note still does not create incoming shift sign-off.

Do not include passwords, signed file links or unnecessary personal details in handover text. Retention/access arrangements for driver contacts, location history and audit records need an agreed policy before live use.

## What a staging operator must provide

Use a dedicated test project and test hostname with fictional data first. The technical steps are in [Deployment](DEPLOYMENT.md), and local setup is in [Testing](TESTING.md). Before a live pilot, the responsible operator must record:

- Environment owner, HTTPS URL, test accounts, customer memberships and the exact application/migration version.
- A configured worker schedule (currently one minute) and monitor schedule (currently five minutes), evidence that both execute, and an alert when they fail.
- An authorised tracking connection with tested provider signatures/vehicle mapping, stale/out-of-order handling and outage recovery. The current gateway accepts a normalised schema; it is not a native Cartrack, Netstar or MiX adapter.
- An agreed routing service and capacity, plus MCY acceptance of ETA freshness, review, material-change and expiry rules.
- Private-file handling, scanning/reconciliation arrangements, retention, backup of both database and file contents, and a successful restore rehearsal.
- Monitoring, escalation contacts, incident escalation, rollout/rollback procedure and recorded UAT results.

These are unfulfilled release gates, not a list of already deployed services. The [roadmap](ROADMAP.md) orders the implementation and acceptance work.
