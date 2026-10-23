import 'server-only';
import { NextResponse } from 'next/server';
import { supabase } from './supabase/server';
import { ZodError } from 'zod';
export async function session(){const db=await supabase();const {data:{user},error}=await db.auth.getUser();if(error||!user)throw new Error('Unauthorised');return {db,user};}
export async function membership(tenant:string,write=false,controller=false){const {db,user}=await session();const {data,error}=await db.from('memberships').select('role').eq('tenant_id',tenant).eq('user_id',user.id).single();if(error||!data||(write&&data.role==='customer_viewer')||(controller&&!['admin','controller'].includes(data.role)))throw new Error('Forbidden');return {db,user,role:data.role};}
export async function mutation(request:Request){const origin=request.headers.get('origin');if(origin&&origin!==new URL(request.url).origin)throw new Error('Forbidden');}
export function failure(error:unknown){const message=error instanceof Error?error.message:'Unexpected error';const status=error instanceof ZodError?400:message==='Unauthorised'?401:message==='Forbidden'?403:message.includes('configured')?503:400;console.error(JSON.stringify({event:'request_failed',status,message:status>=500?'Service unavailable':message}));return NextResponse.json({error:status>=500?'Service unavailable. Contact your administrator.':message},{status});}
export async function rateLimit(db:Awaited<ReturnType<typeof supabase>>,key:string,limit=60){const {data,error}=await db.rpc('consume_rate_limit',{bucket_key:key,max_requests:limit});if(error||!data)throw new Error('Rate limit exceeded or limiter unavailable');}
