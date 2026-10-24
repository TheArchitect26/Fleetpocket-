import { NextResponse } from 'next/server';
import { z } from 'zod';
import { membership,mutation,rateLimit,failure } from '@/lib/server';
const schema=z.object({tenant_id:z.string().uuid(),group_name:z.string().min(1).max(80).default('General fleet'),fleet_no:z.string().min(2).max(40),horse_reg:z.string().min(2).max(40),trailer_one:z.string().max(40),trailer_two:z.string().max(40),name:z.string().min(2).max(100),phone:z.string().min(8).max(30),licence_expiry:z.iso.date(),prdp_expiry:z.iso.date()});
export async function POST(request:Request){try{await mutation(request);const input=schema.parse(await request.json());const {db,user}=await membership(input.tenant_id,true,true);await rateLimit(db,`${user.id}:fleet`,20);const {data,error}=await db.rpc('create_fleet_vehicle',{payload:input});if(error)throw new Error('Unable to create vehicle. Check duplicate fleet number.');return NextResponse.json({id:data},{status:201});}catch(e){return failure(e);}}
