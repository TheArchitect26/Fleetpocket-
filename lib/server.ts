import 'server-only';
import { NextResponse } from 'next/server';
import { supabase } from './supabase/server';
import { ZodError } from 'zod';
export class HttpError extends Error {
 constructor(message:string,public status:number){super(message);}
}
export async function session(){
 const db=await supabase();
 const {data:{user},error}=await db.auth.getUser();
 if(error||!user)throw new HttpError('Unauthorised',401);
 return {db,user};
}
export async function membership(tenant:string,write=false,controller=false){
 const {db,user}=await session();
 const {data,error}=await db.from('memberships').select('role').eq('tenant_id',tenant).eq('user_id',user.id).single();
 if(error||!data||(write&&data.role==='customer_viewer')||(controller&&!['admin','controller'].includes(data.role)))throw new HttpError('Forbidden',403);
 return {db,user,role:data.role};
}
export async function mutation(request:Request){
 const origin=request.headers.get('origin');
 if(origin){
  const url=new URL(request.url);
  const expected=process.env.APP_ORIGIN?new URL(process.env.APP_ORIGIN).origin:`${url.protocol}//${request.headers.get('host')||url.host}`;
  if(origin!==expected)throw new HttpError('Request origin is not permitted',403);
 }
}
export function databaseError(error:{code?:string;message?:string}|null){
 if(!error)return;
 const status=error.code==='42501'?403:error.code==='P0002'?404:['40001','23505'].includes(error.code||'')?409:['23514','23503','22003','22P02'].includes(error.code||'')?422:500;
 throw new HttpError(status===500?'Database operation failed':error.message||'Operation rejected',status);
}
export function failure(error:unknown){
 const requestId=crypto.randomUUID();
 const status=error instanceof HttpError?error.status:error instanceof ZodError||error instanceof SyntaxError?400:error instanceof Error&&error.message.includes('configured')?503:500;
 const message=error instanceof ZodError?'Invalid request fields':status>=500?'Service unavailable. Retry or contact your administrator.':error instanceof Error?error.message:'Request failed';
 console.error(JSON.stringify({event:'request_failed',status,request_id:requestId}));
 return NextResponse.json({error:message,request_id:requestId},{status,headers:status===429?{'Retry-After':'60'}:undefined});
}
export async function rateLimit(db:Awaited<ReturnType<typeof supabase>>,key:string,limit=60){
 const {data,error}=await db.rpc('consume_rate_limit',{bucket_key:key,max_requests:limit});
 databaseError(error);
 if(!data)throw new HttpError('Too many requests. Retry in one minute.',429);
}
