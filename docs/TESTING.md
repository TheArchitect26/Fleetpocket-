# Fleet Pocket testing handover

See the [user guide](USER_GUIDE.md) for product workflows and [latest audit](AUDIT-2026-10-25.md) for open acceptance issues.

This is a development testing candidate. Use fictional data and a dedicated local checkout. Live tracking, WhatsApp delivery, production hosting and operational backup/monitoring are not configured.

## Quick visual test

Install Node.js 22+, then:

```sh
npm ci
npm run testing:check
npm run testing:demo
```

Open http://127.0.0.1:3000. No login is needed. Three fictional companies and twelve vehicles are included. Changes stay in browser local storage; use Reset demo in settings to restore them. Demo uploads save metadata only and all GPS is explicitly simulated. This mode tests navigation, tables, filters, dispatch interaction and message previews, not database isolation or real file handling.

The launcher refuses local `.env` files, which Next.js could use to override isolated settings. Use a separate checkout instead of moving a production configuration into a testing session.

## Authenticated local testing

Install and start Docker, install Supabase CLI and OpenSSL, and install Chromium once:

```sh
npx playwright install chromium
npm run testing:serve
```

The command starts the project's local Supabase, creates isolated fictional tenants and accounts, builds the app and serves http://127.0.0.1:3100/login with a local TLS routing substitute. It does **not** reset an existing database or send invitation emails. Existing local Supabase migrations must already be current; use a fresh checkout/project for a clean run. If migration changes are needed on a populated local database, follow the deployment migration instructions rather than resetting data automatically.

Account emails and the local-only password are saved privately in ignored `tests/.integration-fixtures.json`. Open that file locally. Do not upload it or paste its contents into bug reports.

| Account key | Intended test |
|---|---|
| controller | Tenant A dispatch, documents, ETA review and operations |
| viewer | Tenant A read-only customer access; only released documents/reviewed ETAs |
| customer_admin | Tenant A job creation, own uploads and customer membership controls |
| outsider | Tenant B operations; cannot access Tenant A data |

The fixture has TEST-0 in Tenant A, TEST-1 in Tenant B and twelve additional ETA test vehicles. It starts without fabricated confirmed GPS. Create jobs and upload fictional PDF/images for manual tests. Automated integration tests inject authenticated synthetic GPS; manually running the workspace alone does not start a GPS feed. Local routing responses are fixed test estimates, not real road-provider results.

Ctrl+C stops the app and routing fixture. Supabase remains running; use `supabase stop` when finished. Repeating setup creates fresh fictional accounts/tenants, so use a disposable local project. Never run `supabase db reset` on data you need to keep. Ports 3000 (demo), 3100 (authenticated app), 4100 (test routing) and Supabase's configured ports must be free. Do not run two test launchers concurrently.

## Automated checks

```sh
npm run lint
npm run typecheck
npm test
npm run test:tooling
npm run build
DEMO_MODE=true npm run test:e2e
npm run test:integration
```

`test:integration` performs the same isolated local setup as `testing:serve`, then runs Playwright and stops the app/routing processes. It runs real database/RLS and HTTP/browser workflows, not mocked database assertions. On Linux, Playwright may additionally require `npx playwright install --with-deps chromium`.

The standalone SQL assertion suite (`npm run test:db`) assumes a clean disposable database and runs in its own CI job. The authenticated launcher exercises real database permissions through HTTP/browser workflows; it does not run global-count SQL fixtures over existing tester data or reset that data.

CI uses the same setup components. The operational remediation passed all three jobs in [run 40207318189](https://github.com/TheArchitect26/Fleetpocket-/actions/runs/40207318189) on application commit `8b52c46d6d2aebaff3700c396392cb67286ea565`. Later application changes require their own checks. Documentation-only commits may follow that tested application version.

## Acceptance checklist

Record pass/fail, browser, commit and evidence for each item:

1. **Fleet and scope:** switch companies in demo; search fleet/driver; inspect single, interlink and trailerless vehicles. In authenticated mode, sign in separately as Tenant A and Tenant B; confirm no other tenant's records appear.
2. **Dispatch:** create a job for TEST-0 with explicit collection/delivery coordinates; advance every stage. Flag and resolve an exception. Repeating an unchanged command must not invalidate ETA. Two sessions should see updates within the 15-second polling window.
3. **POD:** deliver a job; verify POD Received is blocked until its matching document is verified. Upload a fictional PDF, preview it, verify it, then release it. A customer must see it only after release; Tenant B must never see it. Finish POD Received and Closed.
4. **Physical load:** deliver job A, load job B on the same vehicle, then finish A's paperwork. Vehicle load must remain Loaded for B.
5. **ETA:** automated HTTP suite verifies twelve vehicles, burst coalescing, outages/retry, exact reviewed publication and material-change withdrawal. Loading ETA must be labelled separately and excluded from delivery performance. No GPS must appear as confirmed before ingestion.
6. **Updates:** generate the MCY template with both trailer rows; preview and approve before Copy/Share. WhatsApp opens a manual share link; this is not delivery confirmation. Due badges update with the clock; the monitor creates due-update incidents. No external reminder delivery is claimed.
7. **Resilience:** preserve map zoom through polling. Failed refresh after a committed job must not duplicate it on retry. Disconnect network and confirm the last snapshot is labelled with a refresh error.
8. **Responsive use:** check navigation, fleet search, drawers and modals on desktop and a narrow mobile viewport. Test keyboard focus and record accessibility issues; a full accessibility assessment remains open.

## Bug reports and exit criteria

Include commit SHA, mode (demo/local authenticated), role, fictional tenant/fleet/job reference, browser, steps, expected/actual results and redacted screenshot. Include API status/request ID when available. Never include keys, cookies, signed download URLs or test-account fixtures. CI retains Playwright traces on failures; treat traces as private because they can contain session data.

Ready for a controlled pilot only after acceptance results are reviewed and the remaining gates in SECOND-REMEDIATION.md are addressed. Current limits include 1,000-record workspace caps, no complete historical SLA reporting, external reminder/escalation delivery and advanced shift workflows, native provider adapters, file scanning/orphan reconciliation, production backup/restore, monitoring and independent security/load tests.


Current regression coverage and migration contracts are listed in [Operational remediation](THIRD-REMEDIATION.md). In UAT, also edit a preview while approval is pending, advance the browser clock across ETA/approval/update due boundaries, acknowledge/own/resolve an incident, and verify one explicit company is required for handovers/access/summaries. For datasets over 1,000 records, use All records and a complete CSV; the overview remains bounded.

After upgrading an existing browser-local demonstration, Reset demo loads the new fictional source/expiry metadata. This resets only fictional browser-local demo changes; it does not reset a configured database.
