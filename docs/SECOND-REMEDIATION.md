# Second audit implementation milestone

This milestone follows [the 24 October re-audit](AUDIT-2026-10-24.md). Historical audit probes describe the old behavior and remain unchanged.

## Implemented changes

| Finding | Change |
|---|---|
| R01 | Only physical delivery empties a truck. Completing an older job's POD or closure preserves a newer load. |
| R02 | Valid same-state dispatch returns the current version without writing, invalidating ETA, or creating audit noise. |
| R03 | One unleased pending calculation per job follows the newest confirmed reading. Every GPS event remains in history. Workers discard obsolete inputs before routing, interleave tenants and drain multiple bounded batches. Each job has a 60-second calculation cooldown. |
| R04 | Calculations and customer publications have separate IDs. Customers see an exact, explicitly reviewed version with its original source and stop. Frequent telemetry does not silently replace that publication or require review of every sample. |
| R05 | Loading ETA has a loading label. Delivery risk and on-time denominators use only valid delivery-stop forecasts; unforecastable deliveries are unknown. Live assignments take precedence over planned and historical jobs in vehicle details. |
| R06 | Workspace data is returned by one SQL statement under the caller's RLS and statement snapshot. |
| R07 | A committed command remains successful if display refresh fails. Job creation takes a tenant-scoped idempotency UUID; identical retries return the same job, different payloads reject with conflict. |
| R09 | Map and viewport persist across refreshes; keyed markers update in place. |
| R12, partial | Tenant-scoped queue health, failed-work detail and guarded manual retry. Worker routing failures return HTTP 503, retain retry work and log a structured degraded event. Incident lifecycle/reopening is still outstanding. |
| R15, partial | New unit, database and authenticated HTTP/browser regressions target these specific failure modes. This is not a production capacity certification. |

## ETA publication policy

A reviewed ETA remains the same immutable estimate value and GPS source. It is valid for at most 15 minutes from review and 30 minutes from the source reading. Approval requires a source no older than 15 minutes. A subsequent calculation within 15 minutes of the reviewed arrival keeps the original publication; a larger difference withdraws it until review. A route/stop change or expiry also withholds it. These are implementation defaults requiring operational sign-off before a pilot.

Fresh calculations use a confirmed GPS source no older than two minutes. A recent source may finish while a newer sample is queued; completion is fenced by route, stop, lease and monotonic completed-source time. The newer sample cannot make an older worker overwrite a newer completed estimate. This is an **as-of road estimate**, never an estimated vehicle position. Staff see calculated provenance, customers see reviewed provenance, and both see source time and target stop. Loading arrival is not a full delivery forecast: loading service time and multi-stop route forecasting remain future work.

The reviewed version can remain visible during a routing outage until its existing expiry. No unreviewed value substitutes for it. GPS and ETA histories retain evidence separately from the coalesced calculation queue.

## Rollout

Apply migrations 010–012 after 001–009 on staging. Pause ingestion and workers for migration 011: it supersedes old leases, deduplicates pending work and installs new queue/publication rules. It preserves approved current versions under the new validity checks. Resume only workers built from this milestone; older workers/publication clients have incompatible assumptions. The service RPC `approved_etas()` now also returns mode and review time. Job-creation clients must supply `idempotency_key` and reuse it for the same submission.

Configure `ETA_WORKER_CONCURRENCY` (default 5, range 1–10), `ETA_WORKER_BUDGET_MS` (default 40000, range 12000–45000) and `ETA_WORKER_MAX_BATCHES` (default 8, range 1–20). Hosting must permit a 60-second request. Default upper bound is 40 calculations per invocation, subject to latency/budget, backlog, cooldown and provider capacity. Run the external scheduler every minute, monitor oldest-ready age and failed counts, and load-test at contracted fleet size. No scheduler or capacity contract has been deployed here.

## Verification and limits

The authenticated integration suite uses real local Supabase and the real HTTP tracking/worker routes, with a deterministic **local TLS routing fixture**, never a live provider. The fixture certificate is trusted only through the CI process environment. Production TLS validation remains enabled. Tests include twelve vehicles, a 60-reading burst, failure/retry, reviewed-publication withdrawal, committed-write refresh failure, idempotency replay, private POD and tenant isolation. This tests correctness under a bounded synthetic scenario, not sustained throughput or native provider compatibility.

Check the linked PR's latest Actions run for actual pass/fail results. Local dependency downloads remain unavailable; syntax and whitespace checks run locally, application/database/browser verification runs in CI. No new pass is implied by a test's existence.

Still open: server pagination and complete exports; wider HTTP error normalization; WhatsApp immutable approvals/reminders; incident lifecycle and missing-POD alerts; combined-tenant action selection; file scanning and orphan reconciliation; provisioning, backups, monitoring, native providers, independent security testing and deployment acceptance; richer fleet/driver editing, historical reporting and component decomposition.
