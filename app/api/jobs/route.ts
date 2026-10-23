import { NextResponse } from 'next/server';
import { z } from 'zod';
import { jobInput,stages } from '@/lib/domain';
import { membership,mutation,rateLimit,failure,databaseError } from '@/lib/server';
export async function POST(request:Request){
 try{
  await mutation(request);
  const input=jobInput.parse(await request.json());
  const {db,user}=await membership(input.tenant_id,true);
  await rateLimit(db,`${user.id}:jobs`);
  const {data,error}=await db.rpc('create_transport_job',{payload:input});
  databaseError(error);
  return NextResponse.json({id:data},{status:201});
 }catch(e){return failure(e);}
}
const command=z.discriminatedUnion('operation',[
 z.object({operation:z.literal('dispatch'),id:z.string().uuid(),tenant_id:z.string().uuid(),expected_version:z.number().int().positive(),status:z.enum([...stages,'Cancelled','Exception','Resolve']),reason:z.string().min(3).max(1000).optional()}),
 z.object({operation:z.literal('approve_eta'),id:z.string().uuid(),tenant_id:z.string().uuid(),eta_id:z.string().uuid()})
]);
export async function PATCH(request:Request){
 try{
  await mutation(request);
  const input=command.parse(await request.json());
  const {db,user}=await membership(input.tenant_id,true,true);
  await rateLimit(db,`${user.id}:dispatch`);
  const result=input.operation==='approve_eta'
   ?await db.rpc('approve_eta',{t:input.tenant_id,j:input.id,expected_eta_id:input.eta_id})
   :await db.rpc('dispatch_job',{t:input.tenant_id,j:input.id,expected_version:input.expected_version,next_status:input.status,reason:input.reason||null});
  databaseError(result.error);
  return NextResponse.json({ok:true,version:result.data});
 }catch(e){return failure(e);}
}
