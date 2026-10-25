import { NextResponse } from 'next/server';
import { supabase } from '@/lib/supabase/server';
import { mutation,failure } from '@/lib/server';
export async function DELETE(request:Request){try{await mutation(request);const db=await supabase();await db.auth.signOut();return NextResponse.json({ok:true});}catch(e){return failure(e);}}
