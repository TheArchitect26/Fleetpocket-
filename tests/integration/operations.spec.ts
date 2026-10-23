import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { test,expect,type Page } from '@playwright/test';
const f=JSON.parse(readFileSync('tests/.integration-fixtures.json','utf8')) as {password:string;tenants:string[];vehicles:string[];users:Record<string,{email:string;id:string}>};
async function client(role:string){
 const db=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{auth:{persistSession:false}});
 const auth=await db.auth.signInWithPassword({email:f.users[role].email,password:f.password});expect(auth.error).toBeNull();return db;
}
async function login(page:Page,role='controller'){
 await page.goto('/login');await page.getByLabel('Email',{exact:true}).fill(f.users[role].email);await page.getByLabel('Password',{exact:true}).fill(f.password);await page.getByRole('button',{name:'Sign in securely'}).click();await expect(page.getByRole('heading',{name:'Your fleet. One clear view.'})).toBeVisible();
}
const errors:string[]=[];
test.beforeEach(async({page})=>{errors.length=0;page.on('pageerror',error=>errors.push(error.message));});
test.afterEach(()=>expect(errors).toEqual([]));
test('configured authentication and raw database permissions fail closed',async({page,request})=>{
 expect((await request.get('/api/workspace')).status()).toBe(401);
 await login(page,'viewer');
 expect((await page.request.patch('/api/jobs',{data:{operation:'dispatch',tenant_id:f.tenants[0],id:crypto.randomUUID(),expected_version:1,status:'Assigned'}})).status()).toBe(403);
 const controller=await client('controller');
 expect((await controller.from('vehicles').update({lat:-29,gps_at:new Date().toISOString()}).eq('id',f.vehicles[0])).error?.code).toBe('42501');
 expect((await controller.from('vehicles').select('id').eq('tenant_id',f.tenants[1])).data).toEqual([]);
 expect((await controller.rpc('claim_eta_work',{batch_size:1})).error?.code).toBe('42501');
 expect((await controller.rpc('enqueue_job_eta',{j:crypto.randomUUID()})).error?.code).toBe('42501');
});
test('real dispatch, exception recovery, private POD verification and closure',async({page,request})=>{
 await login(page);
 await page.getByRole('button',{name:'Create job',exact:true}).click();
 const form=page.getByRole('dialog',{name:'Create transport job'});
 await form.getByLabel('Loading customer',{exact:true}).fill('Integration collection');await form.getByLabel('Offloading customer',{exact:true}).fill('Integration delivery');await form.getByLabel('Cargo',{exact:true}).fill('Integration pallets');await form.getByLabel(/Scheduled delivery/).fill('2027-01-10T12:00');await form.getByRole('button',{name:'Create transport job'}).click();await expect(form).toHaveCount(0);
 await page.getByRole('button',{name:'Jobs & dispatch',exact:true}).click();
 const card=page.locator('.dispatch-card').filter({hasText:'Integration collection'});
 for(const stage of ['Assigned','Accepted','En Route to Loading','At Loading','Loaded','In Transit']){
  await card.getByRole('button',{name:'Advance stage'}).click();await expect(card.getByText(stage,{exact:true})).toBeVisible();
 }
 let response=await page.request.get('/api/workspace');expect(response.ok()).toBeTruthy();let workspace=await response.json();const job=workspace.jobs.find((j:{loading_customer:string})=>j.loading_customer==='Integration collection');
 expect(workspace.vehicles.find((v:{id:string})=>v.id===f.vehicles[0]).load_status).toBe('Loaded');
 await card.getByTitle('Flag exception').click();let dialog=page.getByRole('dialog',{name:'exception'});await dialog.getByLabel('Exception reason').fill('Tyre inspection');await dialog.getByRole('button',{name:'Record exception'}).click();await expect(card.getByText('Exception',{exact:true})).toBeVisible();
 await card.getByRole('button',{name:'Resolve exception'}).click();dialog=page.getByRole('dialog',{name:'exception'});await dialog.getByLabel('Resolution note').fill('Inspection passed');await dialog.getByRole('button',{name:'Resolve and resume'}).click();await expect(card.getByText('In Transit',{exact:true})).toBeVisible();
 for(const stage of ['At Delivery','Delivered']){await card.getByRole('button',{name:'Advance stage'}).click();await expect(card.getByText(stage,{exact:true})).toBeVisible();}
 await card.getByRole('button',{name:'Advance stage'}).click();await expect(page.getByRole('status').filter({hasText:'verified proof of delivery'})).toBeVisible();
 await page.getByRole('button',{name:'Documents & PODs',exact:true}).click();await page.getByRole('button',{name:'Upload document'}).click();dialog=page.getByRole('dialog',{name:'Upload document'});await dialog.getByLabel('Document type').selectOption('Proof of delivery');await dialog.getByLabel('Related job').selectOption(job.id);await dialog.getByLabel('File',{exact:true}).setInputFiles({name:'integration-pod.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\n%%EOF')});await dialog.getByRole('button',{name:'Upload document',exact:true}).click();await expect(dialog).toHaveCount(0);
 workspace=await (await page.request.get('/api/workspace')).json();const doc=workspace.documents.find((d:{name:string})=>d.name==='integration-pod.pdf');expect(doc).toBeTruthy();
 const viewer=await client('viewer'),outsider=await client('outsider'),customerAdmin=await client('customer_admin');
 const alias=await customerAdmin.from('documents').insert({tenant_id:f.tenants[0],name:'Private alias',kind:'Other',vehicle_id:f.vehicles[0],path:doc.path});expect(alias.error?.code).toBe('42501');
 expect((await viewer.from('documents').select('id').eq('id',doc.id)).data).toEqual([]);expect((await viewer.storage.from('fleet-documents').createSignedUrl(doc.path,60)).error).toBeTruthy();
 const documentRow=page.getByRole('row').filter({hasText:'integration-pod.pdf'});await documentRow.getByRole('button',{name:'Verify',exact:true}).click();await expect(documentRow.getByText('Verified',{exact:true})).toBeVisible();
 expect((await viewer.from('documents').select('id').eq('id',doc.id)).data).toEqual([]);
 await documentRow.getByRole('button',{name:'Release to customer'}).click();await expect(documentRow.getByText('Customer released',{exact:true})).toBeVisible();
 expect((await viewer.from('documents').select('id').eq('id',doc.id)).data).toHaveLength(1);expect((await outsider.from('documents').select('id').eq('id',doc.id)).data).toEqual([]);expect((await outsider.storage.from('fleet-documents').createSignedUrl(doc.path,60)).error).toBeTruthy();
 const signed=await viewer.storage.from('fleet-documents').createSignedUrl(doc.path,60);expect(signed.error).toBeNull();const download=await request.get(signed.data!.signedUrl);expect(download.ok()).toBeTruthy();expect((await download.body()).toString()).toContain('%PDF-1.4');
 await page.getByRole('button',{name:'Jobs & dispatch',exact:true}).click();for(const stage of ['POD Received','Closed']){await card.getByRole('button',{name:'Advance stage'}).click();await expect(card.getByText(stage,{exact:true})).toBeVisible();}
 response=await page.request.get('/api/workspace');workspace=await response.json();expect(workspace.vehicles.find((v:{id:string})=>v.id===f.vehicles[0]).load_status).toBe('Empty');expect(workspace.audit.some((a:{before_record?:{status:string};after_record?:{status:string}})=>a.before_record?.status==='Delivered'&&a.after_record?.status==='POD Received')).toBe(true);
});
test('a second controller session receives changes without reloading',async({page})=>{
 await login(page);const controller=await client('controller');const registration=`SYNC-${Date.now()}`;
 const update=await controller.from('vehicles').update({horse_reg:registration}).eq('id',f.vehicles[0]);expect(update.error).toBeNull();
 await expect(page.getByRole('row',{name:'Open TEST-0'})).toContainText(registration,{timeout:25000});
});

test('customer admin can register only their own uploaded objects',async()=>{
 const admin=await client('customer_admin'),viewer=await client('viewer');
 const path=`${f.tenants[0]}/${crypto.randomUUID()}.pdf`;
 const upload=await admin.storage.from('fleet-documents').upload(path,Buffer.from('%PDF-1.4\n%%EOF'),{contentType:'application/pdf'});expect(upload.error).toBeNull();
 const registered=await admin.from('documents').insert({tenant_id:f.tenants[0],name:'Customer instructions',kind:'Delivery instructions',vehicle_id:f.vehicles[0],path}).select('id').single();expect(registered.error).toBeNull();
 expect((await admin.storage.from('fleet-documents').createSignedUrl(path,60)).error).toBeNull();
 expect((await viewer.from('documents').select('id').eq('id',registered.data!.id)).data).toEqual([]);
 expect((await viewer.storage.from('fleet-documents').createSignedUrl(path,60)).error).toBeTruthy();
});
