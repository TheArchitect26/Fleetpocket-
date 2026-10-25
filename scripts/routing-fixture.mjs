// Local deterministic routing substitute. Never deployed with the application.
import { createServer } from 'node:https';
import { readFileSync } from 'node:fs';
let duration=3600,fail=false,calls=0;
createServer({key:readFileSync(process.env.FLEET_TEST_KEY_PATH||'/tmp/fleet-routing-key.pem'),cert:readFileSync(process.env.FLEET_TEST_CERT_PATH||'/tmp/fleet-routing-cert.pem')},(req,res)=>{
 const url=new URL(req.url,'https://localhost:4100');
 res.setHeader('content-type','application/json');
 if(url.pathname==='/control'){duration=Number(url.searchParams.get('duration')||duration);fail=url.searchParams.get('fail')==='true';res.end(JSON.stringify({calls,duration,fail}));return;}
 if(url.pathname==='/health'){res.end('{}');return;}
 if(url.pathname.startsWith('/route/v1/driving/')){calls++;res.statusCode=fail?503:200;res.end(JSON.stringify(fail?{error:'injected outage'}:{code:'Ok',routes:[{duration}]}));return;}
 res.statusCode=404;res.end('{}');
}).listen(4100,'127.0.0.1');
