'use client';
import { useCallback,useEffect,useRef,useState } from 'react';
import { createDemo } from '@/lib/demo';
import type { Workspace } from '@/lib/domain';
export function useWorkspace(demo:boolean){
 const [data,setData]=useState<Workspace|null>(null);
 const [syncError,setSyncError]=useState('');
 const [lastSynced,setLastSynced]=useState<string|null>(null);
 const inFlight=useRef<Promise<Workspace>|null>(null);
 const request=useRef<AbortController|null>(null);
 const refresh=useCallback(async()=>{
  if(inFlight.current)return inFlight.current;
  request.current=new AbortController();
  const task=(async()=>{
   try{
    const response=await fetch('/api/workspace',{cache:'no-store',signal:request.current?.signal});
    if(!response.ok)throw new Error(response.status===401?'Session expired. Sign in again.':'Workspace refresh failed. Showing the last successful snapshot.');
    const result:Workspace=await response.json();
    setData(result);setLastSynced(result.synced_at||new Date().toISOString());setSyncError('');return result;
   }catch(error){
    if(!(error instanceof Error&&error.name==='AbortError'))setSyncError(error instanceof Error?error.message:'Workspace unavailable');
    throw error;
   }finally{inFlight.current=null;}
  })();
  inFlight.current=task;return task;
 },[]);
 useEffect(()=>{
  if(demo){Promise.resolve().then(()=>{let initial=createDemo();try{const saved=localStorage.getItem('mcy-fleet-demo-v1');if(saved)initial=JSON.parse(saved);}catch{}setData(initial);setLastSynced(new Date().toISOString());});return;}
  const update=()=>{if(document.visibilityState==='visible')void refresh().catch(()=>{});};
  update();const timer=window.setInterval(update,15000);
  window.addEventListener('focus',update);document.addEventListener('visibilitychange',update);
  return()=>{window.clearInterval(timer);window.removeEventListener('focus',update);document.removeEventListener('visibilitychange',update);request.current?.abort();};
 },[demo,refresh]);
 useEffect(()=>{if(data?.demo){try{localStorage.setItem('mcy-fleet-demo-v1',JSON.stringify(data));}catch{}}},[data]);
 return {data,setData,refresh,syncError,lastSynced};
}
