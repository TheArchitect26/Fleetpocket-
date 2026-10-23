import { NextResponse } from 'next/server';
import { z } from 'zod';
import { membership,mutation,rateLimit,failure } from '@/lib/server';
import { OperationsAi } from '@/lib/providers';
export async function POST(request:Request){try{await mutation(request);const {tenant_id}=z.object({tenant_id:z.string().uuid()}).parse(await request.json());const {db,user}=await membership(tenant_id,false,true);await rateLimit(db,`${user.id}:summary`,5);const {data:alerts,error}=await db.from('alerts').select('severity,acknowledged').eq('tenant_id',tenant_id);if(error)throw new Error('Summary source unavailable');const open=alerts?.filter(a=>!a.acknowledged)||[];const result=await new OperationsAi().summarise(`${open.length} open alerts, ${open.filter(a=>a.severity==='critical').length} critical alerts in the selected customer fleet`);return NextResponse.json(result);}catch(e){return failure(e);}}
