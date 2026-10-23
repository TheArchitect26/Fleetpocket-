import { NextResponse } from 'next/server';
import { z } from 'zod';
import { membership,mutation,rateLimit,failure } from '@/lib/server';
export async function POST(request:Request){try{await mutation(request);const input=z.object({tenant_id:z.string().uuid(),note:z.string().min(1).max(2000)}).parse(await request.json());const {db,user}=await membership(input.tenant_id,true,true);await rateLimit(db,`${user.id}:handover`,20);const {error}=await db.rpc('record_handover',{t:input.tenant_id,note:input.note});if(error)throw new Error('Unable to record handover');return NextResponse.json({ok:true});}catch(e){return failure(e);}}
