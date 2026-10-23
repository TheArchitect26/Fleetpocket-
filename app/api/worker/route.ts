import { NextResponse } from 'next/server';
import { workerDb,secretMatches } from '@/lib/worker';
import { OsrmRouting } from '@/lib/providers';
import { failure,databaseError } from '@/lib/server';
export const maxDuration=60;
type Work={id:string;lease_token:string;from_lat:number;from_lng:number;recorded_at:string;to_lat:number;to_lng:number};
export async function POST(request:Request){
 try{
  if(!secretMatches(request.headers.get('authorization'),process.env.CRON_SECRET?`Bearer ${process.env.CRON_SECRET}`:undefined))return NextResponse.json({error:'Unauthorised'},{status:401});
  const db=workerDb();
  const claimed=await db.rpc('claim_eta_work',{batch_size:5});
  databaseError(claimed.error);
  const results=await Promise.allSettled(((claimed.data||[]) as Work[]).map(async work=>{
   try{
    const route=await new OsrmRouting().eta([work.from_lng,work.from_lat],[work.to_lng,work.to_lat],new Date(work.recorded_at));
    if(!route)throw new Error('routing_unavailable');
    const result=await db.rpc('finish_eta_work',{work_id:work.id,token:work.lease_token,new_eta:route.eta,route_provider:route.provider});
    databaseError(result.error);
    return result.data?'completed':'superseded';
   }catch{
    const failed=await db.rpc('fail_eta_work',{work_id:work.id,token:work.lease_token,error_code:'routing_or_persistence_failure'});
    databaseError(failed.error);
    return 'retry_or_failed';
   }
  }));
  const rejected=results.filter(r=>r.status==='rejected').length;
  if(rejected)console.error(JSON.stringify({event:'eta_worker_failure',count:rejected}));
  return NextResponse.json({claimed:results.length,results:results.map(r=>r.status==='fulfilled'?r.value:'lease_or_persistence_failure')},{status:rejected?503:200});
 }catch(e){return failure(e);}
}
