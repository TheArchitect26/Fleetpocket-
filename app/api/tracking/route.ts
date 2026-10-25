import { NextResponse } from 'next/server';
import { gpsInput } from '@/lib/domain';
import { workerDb,secretMatches } from '@/lib/worker';
import { failure,databaseError,HttpError } from '@/lib/server';
export async function POST(request:Request){
 try{
  if(!secretMatches(request.headers.get('authorization'),process.env.TRACKING_WEBHOOK_SECRET?`Bearer ${process.env.TRACKING_WEBHOOK_SECRET}`:undefined))return NextResponse.json({error:'Unauthorised'},{status:401});
  // The ingress must also cap streamed bodies; do not trust Content-Length alone.
  const reader=request.body?.getReader();
  if(!reader)throw new HttpError('Request body required',400);
  const decoder=new TextDecoder();let size=0,body='';
  while(true){const chunk=await reader.read();if(chunk.done)break;size+=chunk.value.byteLength;if(size>8192){await reader.cancel();throw new HttpError('Payload too large',413);}body+=decoder.decode(chunk.value,{stream:true});}
  body+=decoder.decode();
  const event=gpsInput.parse(JSON.parse(body));
  if(event.tenant_id!==process.env.TRACKING_TENANT_ID||event.provider!==process.env.TRACKING_PROVIDER)throw new HttpError('Forbidden',403);
  const {data,error}=await workerDb().rpc('ingest_gps',{payload:event});
  databaseError(error);
  return NextResponse.json({accepted:true,duplicate_or_old:!data,processing:'durable queue'},{status:data?202:200});
 }catch(e){return failure(e);}
}
