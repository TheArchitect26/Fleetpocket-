import 'server-only';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
export function demoAllowed(){return process.env.DEMO_MODE==='true'||(process.env.NODE_ENV==='development'&&process.env.DEMO_MODE!=='false');}
export function configured(){return !!(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);}
export async function supabase(){if(!configured())throw new Error('Supabase is not configured');const store=await cookies();return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{cookies:{getAll:()=>store.getAll(),setAll:items=>{try{items.forEach(({name,value,options})=>store.set(name,value,options));}catch{/* Server Components cannot write cookies; proxy refreshes the session. */}}}});}
