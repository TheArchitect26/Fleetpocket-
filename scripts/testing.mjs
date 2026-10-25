// Repeatable, local-only test environment. Never resets a database or emails users.
import { dotenvConflicts } from './testing-preflight.mjs';
import { spawn,spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdtemp,readFile,writeFile,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const mode=process.argv[2]||'check';
if(!['check','demo','integration','serve'].includes(mode))throw new Error('Use check, demo, integration or serve');
const issues=[];
if(Number(process.versions.node.split('.')[0])<22)issues.push('Node.js 22 or newer is required');
if(!existsSync('node_modules/next/package.json'))issues.push('Run npm ci first');
// Next dotenv files override parts of process.env. Refuse them for isolated fixtures.
for(const name of dotenvConflicts())issues.push(`Move ${name} outside this checkout before running isolated testing`);
if(!issues.length&&(mode==='integration'||mode==='serve'))for(const cmd of ['supabase','docker','openssl'])if(spawnSync(cmd,cmd==='openssl'?['version']:['--version'],{stdio:'ignore'}).status!==0)issues.push(`Install ${cmd} and put it on PATH`);
if(issues.length){console.error(issues.map(i=>`• ${i}`).join('\n'));process.exit(1);}
if(mode==='check'){console.log('Local prerequisites passed. Authenticated testing also requires Docker, Supabase CLI and OpenSSL.');process.exit(0);}
const env={...process.env,DEMO_MODE:'true',APP_ORIGIN:'http://127.0.0.1:3000'};
for(const key of ['NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','CRON_SECRET','TRACKING_WEBHOOK_SECRET','TRACKING_TENANT_ID','AI_API_KEY','AI_BASE_URL','AI_MODEL','ROUTING_BASE_URL'])delete env[key];
const children=new Set();let temporary;
function stopChildren(){for(const child of children){try{if(process.platform==='win32')child.kill('SIGTERM');else process.kill(-child.pid,'SIGTERM');}catch{ /* Child already exited. */ }}}
function run(command,args,options={}){return new Promise((resolve,reject)=>{const child=spawn(command,args,{env,stdio:'inherit',detached:process.platform!=='win32',...options});children.add(child);child.on('error',reject);child.on('exit',code=>{children.delete(child);code===0?resolve():reject(new Error(`${command} exited ${code}`));});});}
function capture(command,args){const r=spawnSync(command,args,{env,encoding:'utf8'});if(r.status!==0)throw new Error(`${command} failed; check local Supabase is running`);return r.stdout;}
async function loadEnv(path){for(const line of (await readFile(path,'utf8')).split('\n')){const i=line.indexOf('=');if(i>0)env[line.slice(0,i)]=line.slice(i+1);}}
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{stopChildren();process.exitCode=130;});
try{
 if(mode==='demo'){console.log('Fictional browser-local demonstration: http://127.0.0.1:3000');await run('npm',['run','dev']);}
 else{
  temporary=await mkdtemp(join(tmpdir(),'fleet-testing-'));
  env.GITHUB_ENV=join(temporary,'environment');env.FLEET_TEST_STATUS_PATH=join(temporary,'supabase.env');env.FLEET_TEST_CERT_PATH=join(temporary,'routing-cert.pem');env.FLEET_TEST_KEY_PATH=join(temporary,'routing-key.pem');
  await writeFile(env.GITHUB_ENV,'',{mode:0o600});
  await run('supabase',['start']);
  await writeFile(env.FLEET_TEST_STATUS_PATH,capture('supabase',['status','-o','env']),{mode:0o600});
  await run('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',env.FLEET_TEST_KEY_PATH,'-out',env.FLEET_TEST_CERT_PATH,'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1']);
  await run('node',['scripts/configure-integration.mjs']);await loadEnv(env.GITHUB_ENV);
  await run('node',['scripts/seed-integration.mjs']);await loadEnv(env.GITHUB_ENV);
  await run('npm',['run','build']);
  if(mode==='integration')await run('npx',['playwright','test','--config=playwright.integration.config.ts']);
  else{
   console.log('Authenticated test workspace: http://127.0.0.1:3100/login\nLocal test accounts: tests/.integration-fixtures.json (private; do not share).\nRouting is a local deterministic substitute. No live GPS or messaging. Ctrl+C stops the app; Supabase remains running.');
   const routing=run('node',['scripts/routing-fixture.mjs']);const app=run('npm',['run','start','--','--port','3100']);
   await Promise.race([routing,app]);stopChildren();await Promise.allSettled([routing,app]);
  }
 }
}catch(error){console.error(error.message);process.exitCode=1;}
finally{stopChildren();if(temporary)await rm(temporary,{recursive:true,force:true});}
