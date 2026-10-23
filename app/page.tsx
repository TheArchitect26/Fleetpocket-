import { redirect } from 'next/navigation';
import { configured,supabase } from '@/lib/supabase/server';
import { ControlTower } from '@/components/control-tower';
export const dynamic='force-dynamic';
export default async function Page(){if(configured()){const db=await supabase();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');}return <ControlTower demo={!configured()}/>;}
