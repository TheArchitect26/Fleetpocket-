import { NextResponse } from 'next/server';
import { z } from 'zod';
import { workerDb,secretMatches } from '@/lib/worker';
import { OsrmRouting } from '@/lib/providers';
import { failure,databaseError,membership } from '@/lib/server';
export const maxDuration=60;
type Work={id:string;lease_token:string;from_lat:number;from_lng:number;recorded_at:string;to_lat:number;to_lng:number};
function setting(name:string,fallback:number,min:number,max:number){const n=Number(process.env[name]);return Number.isFinite(n)&&n>=min?Math.min(max,Math.floor(n)):fallback;}
export async function POST(request:Request){
 try{
  if(!secretMatches(request.headers.get('authorization'),process.env.CRON_SECRET?`Bearer ${process.env.CRON_SECRET}`:undefined))return NextResponse.json({error:'Unauthorised'},{status:401});
  const db=workerDb(),started=Date.now();
  const concurrency=setting('ETA_WORKER_CONCURRENCY',5,1,10),budget=setting('ETA_WORKER_BUDGET_MS',40000,12000,45000),maxBatches=setting('ETA_WORKER_MAX_BATCHES',8,1,20);
  const results:string[]=[];
  for(let batch=0;batch<maxBatches&&Date.now()-started<budget-10000;batch++){
   const claimed=await db.rpc('claim_eta_work',{batch_size:concurrency});databaseError(claimed.error);
   const work=(claimed.data||[]) as Work[];if(!work.length)break;
   const settled=await Promise.allSettled(work.map(async item=>{
    try{
     const route=await new OsrmRouting().eta([item.from_lng,item.from_lat],[item.to_lng,item.to_lat],new Date(item.recorded_at));
     if(!route)throw new Error('routing_unavailable');
     const done=await db.rpc('finish_eta_work',{work_id:item.id,token:item.lease_token,new_eta:route.eta,route_provider:route.provider});databaseError(done.error);
     return done.data?'completed':'superseded';
    }catch{
     const failed=await db.rpc('fail_eta_work',{work_id:item.id,token:item.lease_token,error_code:'routing_or_persistence_failure'});databaseError(failed.error);
     return 'routing_failed';
    }
   }));
   results.push(...settled.map(r=>r.status==='fulfilled'?r.value:'lease_or_persistence_failure'));
  }
  const health=await db.rpc('worker_queue_health');databaseError(health.error);
  const failures=results.filter(r=>r==='routing_failed'||r==='lease_or_persistence_failure').length;
  if(failures)console.error(JSON.stringify({event:'eta_worker_degraded',failures}));
  return NextResponse.json({processed:results.length,completed:results.filter(r=>r==='completed').length,superseded:results.filter(r=>r==='superseded').length,failures,healthy:failures===0,queue:health.data,results},{status:failures?503:200});
 }catch(error){return failure(error);}
}
export async function GET(request:Request){
 try{
  const tenant=z.string().uuid().parse(new URL(request.url).searchParams.get('tenant_id'));
  const {db}=await membership(tenant,false,true);
  const health=await db.rpc('eta_queue_health',{t:tenant});databaseError(health.error);
  return NextResponse.json(health.data,{headers:{'Cache-Control':'no-store'}});
 }catch(error){return failure(error);}
}
