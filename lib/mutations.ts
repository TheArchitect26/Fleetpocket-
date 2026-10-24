/** A failed display refresh cannot undo or report failure for a committed command. */
export async function commitAndRefresh<T>(commit:()=>Promise<T>,refresh:()=>Promise<unknown>,onRefreshFailure:()=>void):Promise<T>{
 const result=await commit();
 try{await refresh();}catch{onRefreshFailure();}
 return result;
}
