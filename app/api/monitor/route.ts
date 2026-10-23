import { NextResponse } from 'next/server';
import { z } from 'zod';
import { workerDb,secretMatches } from '@/lib/worker';
import { membership,mutation,failure } from '@/lib/server';
export async function POST(request:Request){try{if(!secretMatches(request.headers.get('authorization'),process.env.CRON_SECRET?`Bearer ${process.env.CRON_SECRET}`:undefined))return NextResponse.json({error:'Unauthorised'},{status:401});const db=workerDb();const {data,error}=await db.rpc('monitor_fleet');if(error)throw new Error('Monitor job failed');return NextResponse.json({ok:true,alerts_created:data});}catch(e){return failure(e);}}
export async function PATCH(request:Request){try{await mutation(request);const input=z.object({id:z.string().uuid(),tenant_id:z.string().uuid()}).parse(await request.json());const {db}=await membership(input.tenant_id,true,true);const {error}=await db.from('alerts').update({acknowledged:true}).eq('id',input.id).eq('tenant_id',input.tenant_id);if(error)throw new Error('Unable to acknowledge alert');return NextResponse.json({ok:true});}catch(e){return failure(e);}}
