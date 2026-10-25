import { NextResponse } from 'next/server';
import { session,failure,databaseError } from '@/lib/server';
export async function GET(){
 try{
  const {db}=await session();
  const {data,error}=await db.rpc('workspace_snapshot');databaseError(error);
  return NextResponse.json(data,{headers:{'Cache-Control':'no-store'}});
 }catch(error){return failure(error);}
}
