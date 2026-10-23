# Audit remediation — implementation milestone

The [23 October audit](AUDIT-2026-10-23.md) records the earlier implementation. This milestone changes the code described there; it does not retroactively make the original findings passing tests. The historical audit probes capture the old behavior and are not the current regression suite.

## Implemented

- F01: authenticated workspace refresh every 15 seconds, focus/visibility refresh, a last-sync indicator, persistent connection failures and manual retry. Requests have a bounded timeout.
- F02: GPS persistence atomically creates durable ETA work. A separate bounded worker claims leases, retries failures and retains failed/superseded work. Duplicate webhook receipt no longer needs to repeat routing.
- F03: ETA completion is fenced by lease, GPS event and route version. Customer approval names the exact ETA record and rejects superseded or stale versions.
- F04: pending, missing, fresh, unavailable and stale ETA states; explicit source/expiry/stop metadata; expired or unpublished estimates are withheld. Stale GPS is labelled in MCY messages. New unconnected vehicles no longer claim confirmed GPS.
- F05: database lifecycle transitions synchronise vehicle load state. Demo transitions use the same load rule.
- F06, partial: separate loading/delivery coordinates and routing to the currently active stop. This is an ETA to that stop, not a complete multi-stop delivery forecast including loading/service time.
- F07: public authenticated clients cannot update confirmed telemetry or load state. Tenant ownership is immutable. Fleet metadata remains editable through its permitted column grants.
- F08: exception reason, interrupted stage and audited resolution; loaded cargo cannot be silently cancelled.
- F09: customer viewers receive only verified, explicitly released POD/loading/delivery documents. Customer admins can also review their own uploads, but can register only Storage objects owned by their Auth identity. Knowing another private path does not grant access. Sensitive driver/insurance types cannot be customer-released. Storage policies use the same rules, including known paths. Verified document identity is immutable.
- F10: a separate real-Supabase authenticated browser suite provisions local-only test identities and exercises dispatch, exception recovery, actual private POD bytes, release, closure, cross-tenant denial and refresh. Existing fictional demo tests remain separate.
- F11/F12, partial: one live assignment per vehicle, matching job/vehicle PODs, optimistic dispatch versions, structured before/after audit snapshots and controller-only operational audit access.
- F14/F15/F18/F19, partial: deterministic newest-first histories, a truncation banner, typed HTTP failure status/request IDs, missing-row/conflict errors for new commands, explicit production demo opt-in and per-tenant capability data.

## Migration and release notes

Apply `006_operational_integrity.sql` then `007_durable_eta.sql` through `009_document_upload_ownership.sql` in a dedicated staging project first. The unique active-assignment index intentionally fails if existing live assignments conflict. Before migrating a populated project, run:

```sql
select tenant_id,vehicle_id,count(*) from jobs
where status in('Assigned','Accepted','En Route to Loading','At Loading','Loaded','In Transit','At Delivery','Exception')
group by tenant_id,vehicle_id having count(*)>1;
```

Reconcile those assignments with operations; the migration does not silently cancel them. Existing unversioned ETAs are not treated as current published estimates. A fresh authorised GPS event and worker calculation establish a versioned ETA. Existing jobs without loading coordinates show unavailable loading ETA until their route data is migrated by a trusted operator.

Dispatch now uses `create_transport_job` / `dispatch_job` RPCs; direct authenticated job writes and telemetry writes are revoked. Integrations using the previous direct writes must migrate. New API dispatch requests include `operation`, `expected_version`, `status` and optional exception/resolution reason. ETA approval includes an exact `eta_id`.

Publication policy is deliberately strict: each new GPS/route ETA version requires review before customer publication, and expires after 15 minutes or when its GPS source reaches 30 minutes of age, whichever comes first. Controllers see pending/unavailable/stale states. This favors honest publication over uninterrupted ETA availability; MCY must review this policy before a live pilot.

Configure an external scheduler to POST `/api/worker` every minute and `/api/monitor` every five minutes using `Authorization: Bearer $CRON_SECRET`. Worker/webhook secrets require at least 32 characters. Set `APP_ORIGIN` to the canonical application URL so browser-origin validation works correctly behind the host proxy. Ingestion returns receipt/queue acceptance, not completed ETA processing. Worker failures retain work for retry; five unsuccessful attempts or expired final leases become failed work. Operational queue review/requeue UI and alert lifecycle improvements remain follow-up work. A scheduler and real tracking provider have not been deployed by this change.

To explicitly run the fictional production-style demo: `DEMO_MODE=true npm run start` after building. Production without Supabase configuration and without that opt-in displays a configuration failure instead of fictional operations.

## Verification

The new code is being validated in PR #1. The previous green CI run predates these migrations and is not evidence that these changes pass. Record the new run after execution. The database suite now includes operational integrity, ETA work and document-release assertions. The authenticated CI job uses a loopback-only Supabase instance, generated local identities and a test-only password; it sends no invitation emails and refuses non-local fixture targets.

## Still required

Native provider signatures/credential registry; deployed workers/scheduler and operating alerts; full multi-stop/service-time forecasting; historical reports; pagination; managed groups; fleet editing/reassignment UI; invitation/MFA/recovery UX; document scanning/quarantine/cleanup; immutable approved WhatsApp records and due reminders; complete role-aware actions in combined tenant views; accessibility primitives; load/security/restore testing; backups, retention and production monitoring.
