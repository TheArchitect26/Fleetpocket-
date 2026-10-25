import test from 'node:test';
import { dotenvConflicts } from './testing-preflight.mjs';
import assert from 'node:assert/strict';
import { mkdtemp,writeFile,readFile,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
test('isolated launcher refuses dotenv files before starting any services',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'fleet-guard-'));
 try{await writeFile(join(dir,'.env.local'),'DEMO_MODE=false');assert.deepEqual(dotenvConflicts(dir),['.env.local']);}finally{await rm(dir,{recursive:true,force:true});}
});
test('configuration refuses non-loopback Supabase and does not export credentials',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'fleet-remote-'));
 try{const input=join(dir,'status'),output=join(dir,'env');await writeFile(input,'API_URL=https://example.com\nANON_KEY=test-anon\nSERVICE_ROLE_KEY=test-private');const r=spawnSync(process.execPath,['scripts/configure-integration.mjs'],{env:{...process.env,FLEET_TEST_STATUS_PATH:input,GITHUB_ENV:output},encoding:'utf8'});assert.equal(r.status,1);assert.match(r.stderr,/local Supabase/);assert.doesNotMatch(r.stdout,/test-private/);await assert.rejects(readFile(output));}finally{await rm(dir,{recursive:true,force:true});}
});
test('local configuration exports isolated credentials without printing them outside Actions',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'fleet-config-'));
 try{const input=join(dir,'status'),output=join(dir,'env');await writeFile(input,'API_URL=http://127.0.0.1:54321\nANON_KEY=test-anon\nSERVICE_ROLE_KEY=test-private');const r=spawnSync(process.execPath,['scripts/configure-integration.mjs'],{env:{...process.env,GITHUB_ACTIONS:'false',FLEET_TEST_STATUS_PATH:input,GITHUB_ENV:output,FLEET_TEST_CERT_PATH:join(dir,'cert.pem')},encoding:'utf8'});assert.equal(r.status,0);assert.equal(r.stdout,'');const config=await readFile(output,'utf8');assert.match(config,/DEMO_MODE=false/);assert.match(config,/CRON_SECRET=[a-f0-9]{64}/);assert.match(config,/NODE_EXTRA_CA_CERTS=/);}finally{await rm(dir,{recursive:true,force:true});}
});
