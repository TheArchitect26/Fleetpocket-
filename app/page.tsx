import { redirect } from 'next/navigation';
import { configured,supabase,demoAllowed } from '@/lib/supabase/server';
import { ControlTower } from '@/components/control-tower';
export const dynamic='force-dynamic';
export default async function Page(){if(!configured()&&!demoAllowed())return <main className="login"><div className="login-card"><h1>Workspace unavailable</h1><p>Authentication is not configured. Contact your administrator.</p></div></main>;if(configured()){const db=await supabase();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');}return <ControlTower demo={!configured()}/>;}
