import { createClient } from '@supabase/supabase-js';
import { writeFile,appendFile } from 'node:fs/promises';
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
if(!url||!['localhost','127.0.0.1'].includes(new URL(url).hostname))throw new Error('Fixtures are restricted to local Supabase');
const db=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const run=crypto.randomUUID().slice(0,8),password='FleetPocket-local-test-only-2026!';
const fixture={password,tenants:[crypto.randomUUID(),crypto.randomUUID()],vehicles:[crypto.randomUUID(),crypto.randomUUID()],users:{},etaFleet:[]};
async function checked(result){if(result.error)throw new Error(result.error.message);return result.data;}
for(const role of ['controller','viewer','outsider','customer_admin']){
 const email=`${role}-${run}@fleet.test`;
 const data=await checked(await db.auth.admin.createUser({email,password,email_confirm:true}));fixture.users[role]={email,id:data.user.id};
}
await checked(await db.from('tenants').insert(fixture.tenants.map((id,i)=>({id,name:`Integration ${i?'B':'A'} ${run}`,code:`${run}${i}`}))));
await checked(await db.from('memberships').insert([
 {tenant_id:fixture.tenants[0],user_id:fixture.users.controller.id,role:'controller'},
 {tenant_id:fixture.tenants[0],user_id:fixture.users.viewer.id,role:'customer_viewer'},
 {tenant_id:fixture.tenants[0],user_id:fixture.users.customer_admin.id,role:'customer_admin'},
 {tenant_id:fixture.tenants[1],user_id:fixture.users.outsider.id,role:'controller'}
]));
for(let i=0;i<2;i++){
 const driver=crypto.randomUUID();
 await checked(await db.from('drivers').insert({id:driver,tenant_id:fixture.tenants[i],name:`Integration Driver ${i}`,phone:'+27 82 555 0199',licence_expiry:'2030-01-01',prdp_expiry:'2030-01-01'}));
 await checked(await db.from('vehicles').insert({id:fixture.vehicles[i],tenant_id:fixture.tenants[i],fleet_no:`TEST-${i}`,horse_reg:`TEST REG ${i}`,driver_id:driver}));
}
for(let i=0;i<12;i++){
 const id=crypto.randomUUID();fixture.etaFleet.push(id);
 await checked(await db.from('vehicles').insert({id,tenant_id:fixture.tenants[0],fleet_no:`ETA-${i.toString().padStart(2,'0')}`,horse_reg:`ETA TEST ${i}`,provider:'Cartrack'}));
}
await appendFile(process.env.GITHUB_ENV,`TRACKING_TENANT_ID=${fixture.tenants[0]}\n`);
await writeFile('tests/.integration-fixtures.json',JSON.stringify(fixture));
console.log('Local integration fixtures ready; no emails sent.');
