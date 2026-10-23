import { readFile,appendFile } from 'node:fs/promises';
const contents=await readFile('/tmp/fleet-supabase.env','utf8');
const values=Object.fromEntries(contents.split('\n').filter(l=>l.includes('=')).map(l=>{const index=l.indexOf('=');return [l.slice(0,index),l.slice(index+1).replace(/^"|"$/g,'')];}));
for(const key of ['API_URL','ANON_KEY','SERVICE_ROLE_KEY'])if(!values[key])throw new Error(`Missing local integration configuration: ${key}`);
if(!['localhost','127.0.0.1'].includes(new URL(values.API_URL).hostname))throw new Error('Integration tests must use local Supabase');
await appendFile(process.env.GITHUB_ENV,`NEXT_PUBLIC_SUPABASE_URL=${values.API_URL}\nNEXT_PUBLIC_SUPABASE_ANON_KEY=${values.ANON_KEY}\nSUPABASE_SERVICE_ROLE_KEY=${values.SERVICE_ROLE_KEY}\nDEMO_MODE=false\nAPP_ORIGIN=http://127.0.0.1:3100\n`);
