import { NextResponse } from 'next/server';
import { z } from 'zod';
import { membership,mutation,rateLimit,failure,databaseError } from '@/lib/server';
const schema=z.object({tenant_id:z.string().uuid(),vehicle_id:z.string().uuid(),job_id:z.string().uuid(),text:z.string().min(30).max(6000),interval_minutes:z.number().int().min(5).max(1440),request_key:z.string().uuid()});
export async function POST(request:Request){try{await mutation(request);const input=schema.parse(await request.json());const {db,user}=await membership(input.tenant_id,true,true);await rateLimit(db,`${user.id}:updates`);const {data,error}=await db.rpc('approve_vehicle_update',{t:input.tenant_id,v:input.vehicle_id,j:input.job_id,body:input.text,minutes:input.interval_minutes,key:input.request_key});databaseError(error);return NextResponse.json(data,{status:201});}catch(e){return failure(e);}}
