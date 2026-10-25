import { existsSync } from 'node:fs';
import { join } from 'node:path';
export function dotenvConflicts(directory='.'){
 return ['.env','.env.local','.env.production','.env.production.local','.env.development','.env.development.local'].filter(name=>existsSync(join(directory,name)));
}
