import { describe,it,expect,vi } from 'vitest';
import { commitAndRefresh } from '../lib/mutations';
describe('committed commands and display refresh',()=>{
 it('preserves a committed result when refresh fails',async()=>{
  const commit=vi.fn().mockResolvedValue({id:'committed'}),refresh=vi.fn().mockRejectedValue(new Error('offline')),notice=vi.fn();
  expect(await commitAndRefresh(commit,refresh,notice)).toEqual({id:'committed'});expect(commit).toHaveBeenCalledTimes(1);expect(notice).toHaveBeenCalledOnce();
 });
 it('does not report success or refresh after a failed command',async()=>{
  const refresh=vi.fn(),notice=vi.fn();await expect(commitAndRefresh(async()=>{throw new Error('rejected');},refresh,notice)).rejects.toThrow('rejected');expect(refresh).not.toHaveBeenCalled();expect(notice).not.toHaveBeenCalled();
 });
});
