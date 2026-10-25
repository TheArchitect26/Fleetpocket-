import { randomBytes } from 'node:crypto';
import { readFile,appendFile } from 'node:fs/promises';
const contents=await readFile(process.env.FLEET_TEST_STATUS_PATH||'/tmp/fleet-supabase.env','utf8');
const values=Object.fromEntries(contents.split('\n').filter(l=>l.includes('=')).map(l=>{const index=l.indexOf('=');return [l.slice(0,index),l.slice(index+1).replace(/^"|"$/g,'')];}));
for(const key of ['API_URL','ANON_KEY','SERVICE_ROLE_KEY'])if(!values[key])throw new Error(`Missing local integration configuration: ${key}`);
if(!['localhost','127.0.0.1'].includes(new URL(values.API_URL).hostname))throw new Error('Integration tests must use local Supabase');
const cronSecret=randomBytes(32).toString('hex'),trackingSecret=randomBytes(32).toString('hex');
if(process.env.GITHUB_ACTIONS==='true')for(const secret of [values.SERVICE_ROLE_KEY,cronSecret,trackingSecret])console.log(`::add-mask::${secret}`);
await appendFile(process.env.GITHUB_ENV,`NEXT_PUBLIC_SUPABASE_URL=${values.API_URL}\nNEXT_PUBLIC_SUPABASE_ANON_KEY=${values.ANON_KEY}\nSUPABASE_SERVICE_ROLE_KEY=${values.SERVICE_ROLE_KEY}\nDEMO_MODE=false\nAPP_ORIGIN=http://127.0.0.1:3100\n`);

await appendFile(process.env.GITHUB_ENV,`CRON_SECRET=${cronSecret}\nTRACKING_WEBHOOK_SECRET=${trackingSecret}\nTRACKING_PROVIDER=Cartrack\nROUTING_BASE_URL=https://127.0.0.1:4100\nNODE_EXTRA_CA_CERTS=${process.env.FLEET_TEST_CERT_PATH||'/tmp/fleet-routing-cert.pem'}\n`);
