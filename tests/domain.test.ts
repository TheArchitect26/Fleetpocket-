import { draftFresh,csvCell,presentJob,canShareUpdate,updateTiming } from '../lib/domain';
import { describe,it,expect } from 'vitest';
import { createDemo,tenantIds } from '../lib/demo';
import { currentJobFor,deliveryTiming,loadStatusFor,isGpsStale,scopeWorkspace,transition,whatsapp,detectAlerts,jobInput,gpsInput,stages,canWrite,canControl } from '../lib/domain';
const now=new Date();
describe('tenant isolation',()=>{
 const data=createDemo(now);
 it('filters every tenant-owned collection',()=>{const scoped=scopeWorkspace(data,[tenantIds[0]]);expect(scoped.tenants).toHaveLength(1);for(const rows of [scoped.vehicles,scoped.drivers,scoped.jobs,scoped.documents,scoped.alerts,scoped.audit,scoped.updates])expect(rows.every(r=>r.tenant_id===tenantIds[0])).toBe(true);expect(scoped.vehicles).toHaveLength(4);});
 it('cannot select an unauthorised tenant',()=>{const scoped=scopeWorkspace(data,[tenantIds[0]],tenantIds[1]);expect(scoped.vehicles).toEqual([]);expect(scoped.jobs).toEqual([]);expect(scoped.tenants).toEqual([]);});
 it('returns nothing without memberships',()=>expect(scopeWorkspace(data,[]).vehicles).toHaveLength(0));
 it('allows combined authorised workspace only',()=>expect(scopeWorkspace(data,tenantIds.slice(0,2)).vehicles).toHaveLength(8));
 it('keeps customer viewers read only',()=>{expect(canWrite('customer_viewer')).toBe(false);expect(canControl('customer_admin')).toBe(false);expect(canControl('controller')).toBe(true);});
});
describe('delivery lifecycle',()=>{
 it('traverses all stages with verified POD',()=>{for(let i=0;i<stages.length-1;i++)expect(transition(stages[i],stages[i+1],true)).toBe(stages[i+1]);});
 it('rejects skipping stages',()=>expect(()=>transition('Created','Loaded',true)).toThrow());
 it('synchronises load state through loading and delivery',()=>{expect(loadStatusFor('Loaded','Empty')).toBe('Loaded');expect(loadStatusFor('Delivered','Loaded')).toBe('Empty');expect(loadStatusFor('Exception','Loaded')).toBe('Loaded');});
 it('does not unload a new trip when old paperwork is completed',()=>{let load=loadStatusFor('Delivered','Loaded');load=loadStatusFor('Loaded',load);expect(loadStatusFor('POD Received',load)).toBe('Loaded');expect(loadStatusFor('Closed',load)).toBe('Loaded');});
 it('prefers a live trip over a planned job',()=>{const d=createDemo(now);const live={...d.jobs[0],status:'In Transit' as const};expect(currentJobFor([{...live,status:'Created'},live],live.vehicle_id)?.status).toBe('In Transit');});
 it('does not score loading arrival against a delivery window',()=>{const d=createDemo(now),j={...d.jobs[0],eta_stop:'loading'};expect(deliveryTiming(j,now.getTime())).toBe('unknown');j.eta_stop='delivery';expect(deliveryTiming(j,now.getTime())).toBe('within window');j.eta_valid_until=new Date(now.getTime()-1000).toISOString();expect(deliveryTiming(j,now.getTime())).toBe('unknown');});
 it('blocks cancellation of loaded cargo',()=>expect(()=>transition('In Transit','Cancelled',false)).toThrow('cargo recovery'));
 it('requires verified POD',()=>expect(()=>transition('Delivered','POD Received',false)).toThrow('verified'));
 it('keeps closed and cancelled jobs terminal',()=>{expect(()=>transition('Closed','Created',true)).toThrow();expect(()=>transition('Cancelled','Assigned',true)).toThrow();});
 it('permits operational exceptions and cancellation',()=>{expect(transition('In Transit','Exception',false)).toBe('Exception');expect(transition('Assigned','Cancelled',false)).toBe('Cancelled');});
});
describe('MCY WhatsApp template',()=>{
 it('populates both trailer rows, route, cargo and explicit simulation label',()=>{const d=createDemo(now);const text=whatsapp(d.vehicles[0],d.jobs[0],d.drivers[0],d.tenants[0]);expect(text.startsWith('L/CPT (Cape Fresh Produce) - D/DBN (Durban Distribution)')).toBe(true);for(const field of ['Transporter:','Fleet No:','Horse Reg:','Status: Empty','Cargo:','\n\nETA:','\n\nLocation:','[SIMULATED]','last GPS:'])expect(text).toContain(field);expect(text.match(/Trailer Reg:/g)).toHaveLength(2);});
 it('supports trailerless vehicles',()=>{const d=createDemo(now);expect(whatsapp(d.vehicles[4],d.jobs[4],undefined,d.tenants[1])).toContain('Trailer Reg: N/A');});
});
describe('tracking and validation',()=>{
 it('flags stale signals without using expired forecasts',()=>{const d=createDemo(now);const alerts=detectAlerts(d.vehicles[2],d.jobs[2],now);expect(alerts.map(a=>a.title)).toEqual(['Stale GPS signal']);});
 it('flags a significant delay from a valid delivery forecast',()=>{const d=createDemo(now);expect(detectAlerts(d.vehicles[7],d.jobs[7],now).map(a=>a.title)).toEqual(['Delivery at risk']);});
 it('does not invent an event for a healthy vehicle',()=>{const d=createDemo(now);expect(detectAlerts(d.vehicles[0],d.jobs[0],now)).toEqual([]);});
 it('rejects GPS coordinates outside Earth',()=>expect(gpsInput.safeParse({tenant_id:tenantIds[0],vehicle_id:createDemo(now).vehicles[0].id,provider:'Cartrack',event_id:'a',lat:91,lng:28,speed:70,recorded_at:now.toISOString()}).success).toBe(false));
 it('rejects incomplete jobs',()=>expect(jobInput.safeParse({cargo:'Steel'}).success).toBe(false));
 it('does not invent a GPS timestamp for an unconnected vehicle',()=>{const d=createDemo(now);d.vehicles[0].gps_at='';d.vehicles[0].location='No confirmed GPS';expect(whatsapp(d.vehicles[0],d.jobs[0],undefined,d.tenants[0])).toContain('No confirmed GPS reading');});
 it('treats missing GPS as stale',()=>{const v=createDemo(now).vehicles[0];v.gps_at='';expect(isGpsStale(v,now.getTime())).toBe(true);});
 it('uses only labelled simulated readings in demo',()=>expect(createDemo(now).vehicles.every(v=>v.simulated)).toBe(true));
});

describe('operational freshness and exact communication approval',()=>{
 it('expires cached ETA value and approval id even without a refresh',()=>{const j={...createDemo(now).jobs[0],eta_valid_until:new Date(now.getTime()-1).toISOString(),eta_id:'old'};const shown=presentJob(j,now.getTime());expect(shown.eta).toBe('');expect(shown.eta_id).toBeNull();expect(deliveryTiming(shown,now.getTime())).toBe('unknown');expect(j.eta).not.toBe('');});
 it('a late approval response cannot authorise changed text or interval',()=>{const a={id:'one',text:'A',interval_minutes:30,vehicle_id:'vehicle',job_id:'job',job_version:1,valid_until:new Date(now.getTime()+60000).toISOString()};expect(canShareUpdate(a,'B',30,'vehicle','job',now.getTime(),1)).toBe(false);expect(canShareUpdate(a,'A',60,'vehicle','job',now.getTime(),1)).toBe(false);expect(canShareUpdate(a,'A',30,'other','job',now.getTime(),1)).toBe(false);expect(canShareUpdate(a,'A',30,'vehicle','job',now.getTime(),2)).toBe(false);expect(canShareUpdate(a,'A',30,'vehicle','job',now.getTime(),1)).toBe(true);expect(canShareUpdate(a,'A',30,'vehicle','job',now.getTime()+60000,1)).toBe(false);});
 it('neutralises leading control characters without dropping original text',()=>{expect(csvCell('\t=1+1')).toBe("\"'\t=1+1\"");expect(csvCell('=1+1')).toBe("\"'=1+1\"");expect(csvCell('normal')).toBe('\"normal\"');});
 it('requires regeneration after a preview source expires',()=>{expect(draftFresh(null,now.getTime())).toBe(true);expect(draftFresh(new Date(now.getTime()+1).toISOString(),now.getTime())).toBe(true);expect(draftFresh(now.toISOString(),now.getTime())).toBe(false);});
 it('updates become due exactly at the scheduled boundary',()=>{const u={id:'u',tenant_id:'t',vehicle_id:'v',text:'approved',approved:true,created_at:now.toISOString(),interval_minutes:30};expect(updateTiming(undefined,now.getTime()).state).toBe('due');expect(updateTiming(u,now.getTime()+30*60000-1).state).toBe('scheduled');expect(updateTiming(u,now.getTime()+30*60000).state).toBe('due');});
});
