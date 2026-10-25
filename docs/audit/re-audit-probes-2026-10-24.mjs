// Read-only probes against the current source. Does not execute PostgreSQL or providers.
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../../',import.meta.url);
const domainSource=await readFile(new URL('lib/domain.ts',root),'utf8');
const controllerSource=await readFile(new URL('components/control-tower.tsx',root),'utf8');
const workerSource=await readFile(new URL('app/api/worker/route.ts',root),'utf8');
const importCode=source=>import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const domain=await importCode(domainSource.replace(/^import .*\n/,'').split('export const jobInput=')[0]);
const observations=[];
{
 let state=domain.loadStatusFor('Delivered','Loaded');
 state=domain.loadStatusFor('Loaded',state);
 assert.equal(state,'Loaded');
 const afterOldPod=domain.loadStatusFor('POD Received',state);
 const afterOldClosure=domain.loadStatusFor('Closed',state);
 assert.equal(afterOldPod,'Empty');assert.equal(afterOldClosure,'Empty');
 observations.push({finding:'R01',method:'actual domain helper',beforeOldPaperwork:state,afterOldPod,afterOldClosure,limitation:'Database trigger has the same rule; database reproduction SQL is supplied separately and was not executed here.'});
}
{
 assert.throws(()=>domain.transition('In Transit','In Transit',false),/one lifecycle stage/);
 observations.push({finding:'R02',method:'actual domain helper positive control',observed:'The frontend lifecycle helper rejects a same-state transition. The database RPC/trigger path requires separate review and has no equivalent rejection.'});
}
{
 const start=controllerSource.indexOf(' async function api(');
 const end=controllerSource.indexOf('\n async function advance(',start);
 assert.ok(start>=0&&end>start);
 const helper=controllerSource.slice(start,end);
 const harness=await importCode(`let writes=0; const fetch=async()=>{writes++;return {ok:true,json:async()=>({id:'committed'})}};const refresh=async()=>{throw new Error('Refresh failed after successful write')};${helper}\nexport async function probe(){let error;try{await api('jobs','POST',{})}catch(e){error=e.message}return {writes,error}}`);
 const first=await harness.probe(),retry=await harness.probe();
 assert.equal(first.writes,1);assert.ok(first.error);assert.equal(retry.writes,2);
 observations.push({finding:'R07',method:'actual extracted API helper with stubbed successful write and failed refresh',first,retry,limitation:'Models the HTTP success/refresh-failure boundary. No real records were created.'});
}
{
 const batch=Number(workerSource.match(/batch_size:(\d+)/)?.[1]);assert.equal(batch,5);
 const vehicles=12,gpsPerVehiclePerMinute=1;
 observations.push({finding:'R03/R04',method:'analytical calculation, not a load benchmark',workerClaimsPerInvocation:batch,documentedInvocationsPerMinute:1,incomingWorkPerMinute:vehicles*gpsPerVehiclePerMinute,minimumBacklogGrowthPerMinute:vehicles*gpsPerVehiclePerMinute-batch,approvalsPerHourIfEveryVersionPublished:vehicles*gpsPerVehiclePerMinute*60});
}
console.log(JSON.stringify({scope:'Pure source-function probes and capacity arithmetic only. No application code changed.',domain_sha256:createHash('sha256').update(domainSource).digest('hex'),observations},null,2));
