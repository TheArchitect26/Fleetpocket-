// Read-only audit witnesses. These expose present behavior, not passing product requirements.
// UI state/label witnesses mirror source branches; they do not render a browser.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
const domain=readFileSync('lib/domain.ts','utf8'),ui=readFileSync('components/control-tower.tsx','utf8');
const extracted=domain.split('\n').find(l=>l.startsWith('export function deliveryTiming'));
const deliveryTiming=runInNewContext(stripTypeScriptTypes(extracted.replace('export ',''))+';deliveryTiming');
const activeLine=ui.split('\n').find(l=>l.startsWith('const active='));
const active=runInNewContext(stripTypeScriptTypes(activeLine)+';active');
const now=Date.parse('2026-10-25T12:00:00Z');
const job={status:'In Transit',eta:'2026-10-25T14:00:00Z',scheduled_at:'2026-10-25T13:00:00Z',eta_stop:'delivery',eta_valid_until:'2026-10-25T11:59:59Z'};
const timing=deliveryTiming(job,now),late=timing==='delayed';
const label=!job.eta?'ETA unavailable':job.eta_stop==='loading'?'Loading stop':late?'Delivery delayed':'Within delivery window';
let draft='Version A',approved=false;const submitted=draft;draft='Version B';approved=false;
// saveUpdate completes after the editable preview has changed.
approved=true;
const saved={created_at:'2026-10-25T10:00:00Z',interval_minutes:30};
const next=Date.parse(saved.created_at)+saved.interval_minutes*60000;
const csv='\t=1+1&" → X"'.replace(/"/g,'""').replace(/^[=+@-]/,"'");
const observations=[
 {finding:'A01',probe:'expired ETA label',domainTiming:timing,currentTableLabel:label,problemReproduced:timing==='unknown'&&label==='Within delivery window'},
 {finding:'A02',probe:'approval completion after editing (state-sequence mirror)',submittedText:submitted,currentPreview:draft,copyEnabled:approved,problemReproduced:approved&&submitted!==draft},
 {finding:'A03',probe:'overdue update badge (label-branch mirror)',overdueMinutes:(now-next)/60000,currentBadge:saved?'Approved update':'Update due',problemReproduced:now>next&&!!saved},
 {finding:'A07',probe:'Created job included by active helper',currentActive:active({status:'Created'}),problemReproduced:active({status:'Created'})},
 {finding:'A14',probe:'CSV leading-tab neutralisation (sanitiser mirror)',leadingTabRemains:csv.startsWith('\t='),problemReproduced:csv.startsWith('\t=')}
];
console.log(JSON.stringify({baseline:'8e8d222 / published application 021e1b37021b96bc5fb3a3064ac8eb082e0e4e5a',method:'Extracted pure helpers plus explicitly mirrored UI/sanitiser branches. No browser, database or spreadsheet execution.',observations},null,2));
if(observations.some(o=>!o.problemReproduced))process.exitCode=1;
