// Read-only audit probes against the actual domain functions; no npm packages needed.
// Node 22.13+ with node:module.stripTypeScriptTypes. This is not the normal test suite.
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
const root = new URL('../../', import.meta.url);
const domainSource = await readFile(new URL('lib/domain.ts', root), 'utf8');
const demoSource = await readFile(new URL('lib/demo.ts', root), 'utf8');
const domainFunctions = domainSource.replace(/^import .*\n/, '').split('export const jobInput=')[0];
const importSource = async source => import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const domain = await importSource(domainFunctions);
const { createDemo } = await importSource(demoSource);
const now = new Date('2026-10-23T12:00:00Z');
const findings = [];
{
 const d = createDemo(now), v = { ...d.vehicles[0], load_status: 'Empty' }, j = { ...d.jobs[0], status: 'At Loading' };
 j.status = domain.transition(j.status, 'Loaded', false);
 const text = domain.whatsapp(v, j, d.drivers[0], d.tenants[0]);
 assert.equal(j.status, 'Loaded'); assert.ok(text.includes('Status: Empty'));
 findings.push({ finding: 'F05', observed: 'A Loaded job and Empty vehicle produce Status: Empty in the MCY update.', outcome: 'reproduced' });
}
{
 const d = createDemo(now), v = { ...d.vehicles[0], gps_at: '2026-10-23T09:00:00Z' };
 const text = domain.whatsapp(v, d.jobs[0], d.drivers[0], d.tenants[0]);
 assert.equal(domain.isGpsStale(v, now.getTime()), true);
 assert.ok(text.includes('last GPS: 2026-10-23T09:00:00.000Z'));
 assert.equal(/stale|overdue/i.test(text), false);
 findings.push({ finding: 'F04', observed: 'A three-hour-old GPS position is included with its timestamp but without a stale warning; the existing ETA remains in the update.', outcome: 'reproduced' });
}
{
 assert.throws(() => domain.transition('Exception', 'In Transit', true), /Resolve the exception/);
 findings.push({ finding: 'F08', observed: 'An Exception job cannot resume In Transit through the lifecycle function.', outcome: 'reproduced; absence of a separate recovery path established by source review' });
}
{
 const d = createDemo(now);
 assert.equal(domain.scopeWorkspace(d, []).vehicles.length, 0);
 assert.equal(domain.scopeWorkspace(d, [d.tenants[0].id], d.tenants[1].id).vehicles.length, 0);
 findings.push({ finding: 'positive-control', observed: 'Pure frontend scoping denies empty or unauthorised tenant selections.', outcome: 'passed; does not replace database RLS tests' });
}
console.log(JSON.stringify({ scope: 'Pure domain functions only. No Zod schemas, React, database, HTTP, storage or external providers executed.', domain_sha256: createHash('sha256').update(domainSource).digest('hex'), probes: findings }, null, 2));
