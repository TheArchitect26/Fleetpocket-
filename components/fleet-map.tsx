'use client';
import { useEffect,useRef,useState } from 'react';
import * as maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import type { Vehicle,Tenant } from '@/lib/domain';
export default function FleetMap({vehicles,tenants,onSelect}:{vehicles:Vehicle[];tenants:Tenant[];onSelect:(id:string)=>void}){
 const el=useRef<HTMLDivElement>(null),map=useRef<maplibregl.Map|null>(null);
 const markers=useRef(new Map<string,maplibregl.Marker>());
 const [failed,setFailed]=useState(false),[zoom,setZoom]=useState(4.4);
 useEffect(()=>{
  if(!el.current)return;
  try{
   const instance=new maplibregl.Map({container:el.current,style:{version:8,sources:{osm:{type:'raster',tiles:['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],tileSize:256,attribution:'© OpenStreetMap contributors'}},layers:[{id:'osm',type:'raster',source:'osm',paint:{'raster-saturation':-.8,'raster-opacity':.8}}]},center:[26,-30],zoom:4.4,attributionControl:{compact:true}});
   map.current=instance;
   instance.addControl(new maplibregl.NavigationControl({showCompass:false}),'top-right');
   instance.on('error',()=>setFailed(true));
   instance.on('idle',()=>{if(instance.areTilesLoaded())setFailed(false);});
   instance.on('moveend',()=>setZoom(instance.getZoom()));
  }catch{queueMicrotask(()=>setFailed(true));}
  const activeMarkers=markers.current;
  return()=>{activeMarkers.forEach(marker=>marker.remove());activeMarkers.clear();map.current?.remove();map.current=null;};
 },[]);
 useEffect(()=>{
  const instance=map.current;if(!instance)return;
  const present=new Set<string>();
  for(const v of vehicles){
   if(!Number.isFinite(v.lat)||!Number.isFinite(v.lng))continue;
   present.add(v.id);let marker=markers.current.get(v.id);
   if(!marker){const node=document.createElement('button');node.className='map-pin';node.textContent='↗';marker=new maplibregl.Marker({element:node}).setLngLat([v.lng,v.lat]).addTo(instance);markers.current.set(v.id,marker);}
   const node=marker.getElement();node.style.background=tenants.find(t=>t.id===v.tenant_id)?.color||'#0e9488';
   node.title=`${v.fleet_no} · ${v.simulated?'Simulated':'Confirmed GPS'}`;node.setAttribute('aria-label',node.title);
   node.onclick=()=>onSelect(v.id);marker.setLngLat([v.lng,v.lat]);
  }
  markers.current.forEach((marker,id)=>{if(!present.has(id)){marker.remove();markers.current.delete(id);}});
 },[vehicles,tenants,onSelect]);
 return <div className="map-shell" data-testid="fleet-map" data-zoom={zoom}><div ref={el} className="map-canvas"/>{failed&&<div className="map-fallback">Map tiles unavailable. Vehicle coordinates remain available in fleet details.</div>}<span className="map-label">{vehicles.every(v=>v.simulated)?'SIMULATED GPS':'LAST RECEIVED GPS'} · SOUTH AFRICA</span><div className="map-legend">{tenants.map(t=><span key={t.id}><i style={{background:t.color}}/>{t.code}</span>)}</div></div>;
}
