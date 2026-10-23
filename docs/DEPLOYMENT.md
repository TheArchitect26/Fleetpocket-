# Deployment and operations

## Environment variables

See `.env.example`. Only the Supabase project URL and anonymous/publishable key are public. Protect the service-role key, webhook credential, cron credential and AI key in the host's server secret store. No live secrets were configured during initial implementation.

- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`: same Supabase project.
- `SUPABASE_SERVICE_ROLE_KEY`: worker-only project key. Never expose to clients.
- `TRACKING_WEBHOOK_SECRET`: random secret of at least 32 characters, sent as `Authorization: Bearer …`.
- `TRACKING_TENANT_ID`, `TRACKING_PROVIDER`: bind that credential to one tenant and authorised provider. Simulator must be selected explicitly.
- `APP_ORIGIN`: canonical external application origin (scheme, host and port), used for browser mutation checks. Set it to the actual staging/production URL; local authenticated CI uses its own loopback origin.
- `DEMO_MODE`: explicit `true` opt-in for fictional demonstrations; keep `false` for live workspaces. Missing Auth configuration otherwise shows an unavailable workspace.
- `CRON_SECRET`: independent random secret, at least 32 characters.
- `ROUTING_BASE_URL`: trusted HTTPS OSRM-compatible service. Public OSRM demo is for development only; obtain commercial/self-hosted capacity for production.
- `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL`: optional trusted OpenAI-compatible service. Missing configuration falls back to labelled rule-based summaries.

## Database setup

```sh
supabase start
supabase db reset
supabase test db
# For a dedicated remote project:
supabase link --project-ref YOUR_PROJECT
supabase db push
```

Migrations `001_foundation.sql` through `008_rpc_permissions.sql` create data, policies, private storage and worker functions. Run in staging first. Do not apply this rebuild to the previous application's database.

Provision tenants and Auth users through the Supabase admin dashboard. Insert explicit membership rows as a trusted administrator. Roles: admin/controller/customer_admin/customer_viewer. Customer admins create jobs/upload documents and manage customer-role membership for existing Auth identities using Team & access. Identity provisioning and email invitations remain an administrator task. Do not grant them service-role access. Disable public signup in remote Auth settings and configure application URL/callback allowlists. No default password or automatically privileged account exists.

## Application host

Deploy to a Node.js host compatible with Next.js 16. Set secrets, install dependencies, run all checks, then `npm run build` / `npm start`. Use TLS. Configure request-body limits (11 MB), request timeouts and platform-level webhook rate limiting. Use separate staging and production projects. Do not enable fictional demo mode on a production hostname; configure Supabase before release.

## Background jobs

An external scheduler must POST `/api/worker` every minute to process durable ETA work, and `/api/monitor` every five minutes with the cron bearer credential. Alert insertion is deduplicated for open alerts. Log the HTTP result, retry transient failures, and alert on repeated failures. No scheduler has been deployed from this workspace.

Tracking gateway POST `/api/tracking` accepts JSON:

```json
{"tenant_id":"TENANT_UUID","vehicle_id":"VEHICLE_UUID","provider":"Cartrack","event_id":"provider-event-123","lat":-29.8587,"lng":31.0218,"speed":72,"recorded_at":"2026-10-23T12:00:00Z"}
```

Register each vehicle's authorised provider. Real Cartrack/Netstar/MiX payload/signature adapters must be completed with provider documentation and test accounts. Current endpoint accepts the normalised schema, not arbitrary native payloads. It rejects future readings over one minute and readings older than one day. Position writes and ETA work creation are atomic. Routing runs in the separate leased worker. Deploy the worker scheduler before expecting computed ETAs. Leases expire after 60 seconds, failed work retries up to five attempts, and completed results are fenced against the exact GPS event and route version. See docs/REMEDIATION.md for publication policy and migration preflight.

## Backups, monitoring and recovery

Enable Supabase daily backups and PITR appropriate to contract/RPO. Test restores into a separate project monthly. Private Storage objects require a separate backup/versioning policy; database backups alone do not protect file content. Define retention for GPS and audit records and implement scheduled retention/purge jobs after legal requirements are agreed.

Connect the host's error/log monitoring with redaction. Review structured `request_failed` events, cron failures, stale-signal trends, upload orphans and worker throughput. No monitoring vendor account or backup policy has been configured automatically. Use a staging-to-production release gate with passing CI, tenant-isolation tests, restore evidence and real-provider acceptance tests.
