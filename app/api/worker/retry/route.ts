import { NextResponse } from 'next/server';
import { z } from 'zod';
import { membership,mutation,rateLimit,databaseError,failure } from '@/lib/server';
export async function POST(request:Request){
 try{
  await mutation(request);const input=z.object({tenant_id:z.string().uuid(),job_id:z.string().uuid()}).parse(await request.json());
  const {db,user}=await membership(input.tenant_id,true,true);await rateLimit(db,`${user.id}:eta_retry`,10);
  const result=await db.rpc('retry_job_eta',{t:input.tenant_id,j:input.job_id});databaseError(result.error);
  return NextResponse.json({ok:true});
 }catch(error){return failure(error);}
}
