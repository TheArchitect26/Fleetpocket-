# Delivery status and remaining work

Implemented across all six phases, with scope limits below. This is not yet production approved.

| Phase | Implemented | Remaining |
|---|---|---|
| 1 | New repository/branch, Next/TS/Tailwind design system, Supabase auth/schema/RLS | Install/build verification, live project provisioning, MFA/password-reset UX |
| 2 | Control tower, tenant filter, fleets/drivers and detail profiles, original responsive UI | Fleet/driver CRUD, vehicle groups within each customer, bulk import |
| 3 | Create/advance jobs, cancellation/exception flags, private upload/preview/verify, POD guard, audit | Rich exception resolution, reassignment, editing routes, per-document ACLs and malware scanning |
| 4 | Normalised authenticated GPS ingestion, idempotency, ETA provider/history, monitor endpoint | Native provider adapters, live acceptance testing, durable queue, deployed scheduler, ETA approval UI |
| 5 | MCY update preview, explicit approval, copy/share/history/interval metadata, AI abstraction | Reminder delivery, per-connection credentials, structured AI anomaly review |
| 6 | Tenant-scoped customer view, job submission, document downloads, snapshot CSV/workload reports, tests/CI/runbook | Customer user-management UI, historical SLA reporting, independent penetration test, backup/restore deployment |

Local dependency installation was blocked by the execution sandbox's network access to its proxy. No local lint/typecheck/unit/browser/build pass is claimed. Test suites and GitHub Actions were authored so verification can run where registry access is available. Update this file with actual CI results before release.

The local workspace had no previous repository. Local commits are on `rebuild/fleet-pocket`. Live Supabase/tracking/AI/messaging credentials and a hosting preview were not configured. Demo mode deliberately keeps no real files and clearly marks all GPS readings as simulated.

Known implementation limits: first 1,000 records per table in workspace read (pagination required before larger deployments); browser-local demo storage is not secure storage; customer-portal selector is scoped to current memberships, and production roles are enforced in the API/RLS; UI approval does not prove a WhatsApp message was delivered; stopping detection is advisory; routing failures retain old ETA values and require controller judgement. Auth refresh currently occurs through server-side Supabase access; add a Next.js session-refresh proxy before long-running production use.
