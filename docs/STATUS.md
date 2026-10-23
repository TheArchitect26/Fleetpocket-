# Delivery status and remaining work

Implemented across all six phases, with scope limits below. This is not yet production approved.

| Phase | Implemented | Remaining |
|---|---|---|
| 1 | New repository/branch, Next/TS/Tailwind design system, Supabase auth/schema/RLS | Live project provisioning, MFA/password-reset UX |
| 2 | Control tower, tenant filter, fleets/drivers and detail profiles, original responsive UI | Fleet/driver editing and deletion, bulk import |
| 3 | Create/advance jobs, cancellation/exception flags, private upload/preview/verify, POD guard, audit | Rich exception resolution, reassignment, editing routes, per-document ACLs and malware scanning |
| 4 | Normalised authenticated GPS ingestion, idempotency, ETA provider/history, monitor endpoint | Native provider adapters, live acceptance testing, durable queue, deployed scheduler |
| 5 | MCY update preview, explicit approval, copy/share/history/interval metadata, AI abstraction | Reminder delivery, per-connection credentials, structured AI anomaly review |
| 6 | Tenant-scoped customer view, job submission, document downloads, snapshot CSV/workload reports, tests/CI/runbook | Auth user provisioning/invitations, historical SLA reporting, independent penetration test, backup/restore deployment |

Local dependency installation was blocked by the execution sandbox's network access to its proxy. GitHub Actions successfully installed dependencies and passed lint, TypeScript, 17 unit tests, a production build and the first 11 database isolation assertions on the preceding revision. Browser workflows and the latest additions are being verified in PR #1; use that PR's latest CI run as the release authority. No local check pass is claimed.

The local workspace had no previous repository. Local commits are on `rebuild/fleet-pocket`. Live Supabase/tracking/AI/messaging credentials and a hosting preview were not configured. Demo mode deliberately keeps no real files and clearly marks all GPS readings as simulated.

Known implementation limits: first 1,000 records per table in workspace read (pagination required before larger deployments); browser-local demo storage is not secure storage; customer-portal selector is scoped to current memberships, and production roles are enforced in the API/RLS; UI approval does not prove a WhatsApp message was delivered; stopping detection is advisory; routing failures retain old ETA values and require controller judgement. A Next.js proxy refreshes Supabase session cookies; test expiry and revocation against the configured project before production.
