# Fleet Pocket · Musa Connect Yield

A clean Next.js/TypeScript rebuild of MCY's multi-customer logistics workspace. This is an implementation candidate, not a certified production release.

## Run

Use Node.js 22 LTS or newer.

```sh
npm ci
cp .env.example .env.local
npm run dev
```

Without Supabase variables, `/` opens a clearly labelled fictional demonstration: 3 companies, 12 vehicles/drivers, jobs, document metadata and alerts. Demo edits persist only in browser local storage. No real documents, GPS, AI output or messages are sent. Reset demo restores fixtures.

With Supabase configured, `/` requires a valid Supabase session. No public sign-up or implicit membership. Apply migrations and provision memberships before inviting users.

## Included

- Responsive control tower, tenant selector, searchable fleet table, MapLibre map, driver/vehicle drawer and status filters.
- Job creation, ordered dispatch lifecycle, exceptions/cancellation and verified-POD closure guard.
- Private PDF/image upload, signature/type/size checks, signed previews, controller verification and document expiry monitoring.
- Exact MCY update format, two trailer rows, editable preview, explicit controller approval, manual copy/share, update history and interval scheduling metadata.
- Tenant-scoped CSV reports, workload overview, alert acknowledgement, handover notes and database audit triggers.
- Supabase Auth, tenant memberships, RLS, tenant-qualified foreign keys and approved-ETA access.
- Authenticated tracking webhook, idempotent GPS ingestion, monotonic confirmed positions, OSRM road ETA abstraction, ETA history and scheduled monitoring endpoint.
- Server-only AI abstraction with deterministic, labelled fallback.

## Verification

```sh
npm run lint
npm run typecheck
npm test
npm run build
npx playwright install chromium
npm run test:e2e
supabase start
supabase test db
```

CI runs these checks on push/PR. Unit tests cover tenant filtering, role permissions, lifecycle guards, MCY formatting, stale GPS and validation. Browser tests cover fleet scoping, create/advance dispatch, approval/history, mobile usability and unauthenticated API rejection. pgTAP exercises actual database RLS and cross-tenant references.

See [deployment](docs/DEPLOYMENT.md), [architecture](docs/ARCHITECTURE.md), and [limitations and delivery status](docs/STATUS.md). Never infer passing checks from the existence of a test file; consult CI results.
