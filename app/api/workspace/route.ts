import { NextResponse } from 'next/server';
import { session,failure,databaseError } from '@/lib/server';
export async function GET(){
 try{
  const {db}=await session();
  const tables=['tenants','vehicles','drivers','jobs','documents','alerts','audit','updates'] as const;
  const result:Record<string,unknown>={demo:false,synced_at:new Date().toISOString()};
  for(const table of tables){
   let query=db.from(table==='jobs'?'visible_jobs':table).select('*').limit(1000);
   if(['audit','updates','documents'].includes(table))query=query.order('created_at',{ascending:false});
   const {data,error}=await query;
   databaseError(error);result[table]=data;
  }
  const etas=await db.rpc('approved_etas');databaseError(etas.error);
  result.jobs=(result.jobs as {id:string}[]).map(j=>({...j,...etas.data?.find((e:{job_id:string})=>e.job_id===j.id),eta:etas.data?.find((e:{job_id:string})=>e.job_id===j.id)?.eta||''}));
  const memberships=await db.from('memberships').select('tenant_id,role');databaseError(memberships.error);
  result.capabilities=Object.fromEntries((memberships.data||[]).map(m=>[m.tenant_id,m.role]));
  result.role=memberships.data?.some(x=>x.role==='admin')?'admin':memberships.data?.some(x=>x.role==='controller')?'controller':memberships.data?.some(x=>x.role==='customer_admin')?'customer_admin':'customer_viewer';
  result.truncated=tables.filter(t=>(result[t] as unknown[]).length===1000);
  return NextResponse.json(result,{headers:{'Cache-Control':'no-store'}});
 }catch(e){return failure(e);}
}
