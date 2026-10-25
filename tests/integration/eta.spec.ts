import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { test,expect } from '@playwright/test';
const f=JSON.parse(readFileSync('tests/.integration-fixtures.json','utf8')) as {password:string;tenants:string[];etaFleet:string[];users:Record<string,{email:string}>};
const url=process.env.NEXT_PUBLIC_SUPABASE_URL!;
if(!['localhost','127.0.0.1'].includes(new URL(url).hostname))throw new Error('Local fixtures only');
async function user(role:string){const db=createClient(url,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{auth:{persistSession:false}});expect((await db.auth.signInWithPassword({email:f.users[role].email,password:f.password})).error).toBeNull();return db;}
test('HTTP tracking bursts coalesce, worker drains twelve vehicles, and reviewed ETAs remain explicit',async({request})=>{
 test.setTimeout(180000);
 const controller=await user('controller'),viewer=await user('viewer'),outsider=await user('outsider');
 const service=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false}});
 const jobs:string[]=[];
 const base={loading_code:'CPT',loading_customer:'ETA collection',delivery_code:'DBN',delivery_customer:'ETA delivery',cargo:'Test pallets',scheduled_at:new Date(Date.now()+86400000).toISOString(),loading_lat:-33.9,loading_lng:18.4,destination_lat:-29.8,destination_lng:31};
 for(const vehicle_id of f.etaFleet){
  const created=await controller.rpc('create_transport_job',{payload:{...base,tenant_id:f.tenants[0],vehicle_id,idempotency_key:crypto.randomUUID()}});expect(created.error).toBeNull();jobs.push(created.data);
  let version=1;for(const status of ['Assigned','Accepted','En Route to Loading']){const advanced=await controller.rpc('dispatch_job',{t:f.tenants[0],j:created.data,expected_version:version,next_status:status});expect(advanced.error).toBeNull();version=advanced.data;}
 }
 async function gps(vehicle_id:string,recorded_at:string){const response=await request.post('/api/tracking',{headers:{Authorization:`Bearer ${process.env.TRACKING_WEBHOOK_SECRET}`},data:{tenant_id:f.tenants[0],vehicle_id,provider:'Cartrack',event_id:crypto.randomUUID(),lat:-33,lng:19,speed:60,recorded_at}});expect(response.status()).toBe(202);}
 const baseline=Date.now();
 for(const vehicle of f.etaFleet){await gps(vehicle,new Date(baseline-30000).toISOString());await gps(vehicle,new Date(baseline-20000).toISOString());}
 const pending=await service.from('tracking_work').select('job_id,event_id').in('job_id',jobs).eq('status','pending');expect(pending.error).toBeNull();expect(pending.data).toHaveLength(12);
 expect((await service.from('tracking_events').select('id').in('vehicle_id',f.etaFleet)).data).toHaveLength(24);
 expect((await outsider.rpc('eta_queue_health',{t:f.tenants[0]})).error?.code).toBe('42501');
 expect((await viewer.rpc('retry_job_eta',{t:f.tenants[0],j:jobs[0]})).error?.code).toBe('42501');
 expect((await request.post('/api/worker')).status()).toBe(401);
 const worker=()=>request.post('/api/worker',{headers:{Authorization:`Bearer ${process.env.CRON_SECRET}`}});
 const first=await worker();expect(first.status()).toBe(200);const result=await first.json();expect(result.completed).toBe(12);expect(result.failures).toBe(0);expect(result.queue.pending).toBe(0);
 const calculated=await controller.rpc('approved_etas');expect(calculated.error).toBeNull();expect(calculated.data.filter((e:{job_id:string})=>jobs.includes(e.job_id)).every((e:{eta_stop:string})=>e.eta_stop==='loading')).toBe(true);
 const original=calculated.data.find((e:{job_id:string})=>e.job_id===jobs[0]);
 expect((await viewer.rpc('approved_etas')).data.find((e:{job_id:string})=>e.job_id===jobs[0]).eta).toBeNull();
 expect((await controller.rpc('approve_eta',{t:f.tenants[0],j:jobs[0],expected_eta_id:original.eta_id})).error).toBeNull();
 // High-cadence GPS remains confirmed history; only one latest unleased calculation is kept.
 const burstStart=Date.now()-10000;
 for(let i=0;i<60;i++)await gps(f.etaFleet[0],new Date(burstStart+i).toISOString());
 expect((await service.from('tracking_work').select('id').eq('job_id',jobs[0]).eq('status','pending')).data).toHaveLength(1);
 expect((await service.from('tracking_events').select('id').eq('vehicle_id',f.etaFleet[0])).data).toHaveLength(62);
 let published=(await viewer.rpc('approved_etas')).data.find((e:{job_id:string})=>e.job_id===jobs[0]);expect(published.eta).toBe(original.eta);expect(published.eta_mode).toBe('reviewed');expect(published.eta_source_at).toBe(original.eta_source_at);
 expect((await worker()).status()).toBe(200); // cooldown does not spend another routing request
 const allowNext=async()=>{expect((await service.from('jobs').update({eta_next_calculation_at:new Date(0).toISOString()}).eq('id',jobs[0])).error).toBeNull();expect((await service.from('tracking_work').update({available_at:new Date(0).toISOString()}).eq('job_id',jobs[0]).eq('status','pending')).error).toBeNull();};
 await allowNext();expect((await (await worker()).json()).completed).toBe(1);
 published=(await viewer.rpc('approved_etas')).data.find((e:{job_id:string})=>e.job_id===jobs[0]);expect(published.eta).toBe(original.eta); // small unreviewed change cannot replace the exact reviewed version
 await request.get('https://127.0.0.1:4100/control?duration=7200',{ignoreHTTPSErrors:true});await gps(f.etaFleet[0],new Date().toISOString());await allowNext();expect((await (await worker()).json()).completed).toBe(1);
 expect((await viewer.rpc('approved_etas')).data.find((e:{job_id:string})=>e.job_id===jobs[0]).eta).toBeNull(); // material change withdraws publication
 await request.get('https://127.0.0.1:4100/control?fail=true',{ignoreHTTPSErrors:true});await gps(f.etaFleet[0],new Date().toISOString());await allowNext();const failed=await worker();expect(failed.status()).toBe(503);expect((await failed.json()).failures).toBe(1);
 expect((await service.from('tracking_work').select('id').eq('job_id',jobs[0]).eq('status','pending')).data).toHaveLength(1);
 await request.get('https://127.0.0.1:4100/control?duration=3600',{ignoreHTTPSErrors:true});expect((await controller.rpc('retry_job_eta',{t:f.tenants[0],j:jobs[0]})).error).toBeNull();expect((await (await worker()).json()).completed).toBe(1);
});
