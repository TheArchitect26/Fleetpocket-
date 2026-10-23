# Architecture

Next.js App Router serves the controller workspace and JSON APIs. UI components use Tailwind v4, a local shadcn-style Button built on Radix Slot/CVA, Lucide icons and MapLibre. No existing application's architecture or code was used.

`lib/domain.ts` owns lifecycle rules, runtime validation, tenant scoping and MCY formatting. `lib/demo.ts` supplies fictional data only. `components/control-tower.tsx` orchestrates the current UI; extraction into feature modules is a next maintainability step as workflows deepen.

Production data lives in Supabase PostgreSQL. Every owned row has `tenant_id`. Memberships explicitly grant customer or controller/admin roles per tenant. No controller automatically receives access to all customers. Composite foreign keys prevent linking a tenant's job to another tenant's vehicle/driver. Supabase RLS remains authoritative when a client bypasses the web API. Browser filtering is usability, not the security boundary.

The app fetches only RLS-authorised records. `visible_jobs` omits raw ETAs; `approved_etas()` exposes an ETA only to controllers or when approved. Every newly computed ETA clears approval. Driver contact/document access currently follows tenant membership; finer document ACLs are a release requirement where customer users should have narrower rights.

Supabase session cookies authenticate web/API requests. Android can reuse the schema and PostgREST/RPC access with Supabase JWTs; web mutation endpoints currently expect cookie sessions. A mobile token-auth middleware and versioned API contract should be added before Android delivery.

Service-role use is confined to `lib/worker.ts`. Tracking webhook credentials are bound to one configured tenant and provider, so possessing one provider credential does not grant arbitrary customer access. Production multi-provider rollout needs a per-connection credential registry and provider-specific signature adapters. `ingest_gps` serialises vehicle updates and records duplicate-safe events, never replacing a newer confirmed reading with an older event. Routing failure retains the last calculated ETA; GPS is never interpolated or fabricated. Monitoring detects stale readings, delay, repeated zero-speed samples in transit and document expiry. Zero speed is a review flag, not a claim about the cause.

AI receives aggregate counts only, runs on the server and provides advisory text. Deterministic fallback is explicit. The original GPS, lifecycle and audit data remain authoritative.

WhatsApp sharing requires approval in the UI, saves an audit-backed update and opens WhatsApp for a human final send. No delivery receipt is claimed. `interval_minutes` stores a reminder schedule; it does not authorise sending future messages automatically.

Storage is private. Object paths begin with tenant UUID and are validated by Storage RLS. Previews expire in 60 seconds. Files are immutable unique object names; metadata failures may leave orphans, requiring reconciliation. MIME magic checks are not malware scanning.
