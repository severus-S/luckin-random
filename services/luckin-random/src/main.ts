import { application } from './server.js';

const mode=process.env.MCP_MODE??'mock';if(mode!=='mock'&&mode!=='live')throw new Error('MCP_MODE must be mock or live');
const host=process.env.HOST??'127.0.0.1';
if(host!=='127.0.0.1'&&host!=='::1')throw new Error('Bind to loopback; expose HTTPS through a local reverse proxy');
const app=application({key:process.env.API_KEY??'',encryptionKey:Buffer.from(process.env.ENCRYPTION_KEY??'','hex'),database:process.env.DATABASE_PATH??'.local/luckin.sqlite',mode,allowLive:process.env.ALLOW_LIVE_ORDERS==='true',contractVerified:process.env.LIVE_CONTRACT_VERIFIED==='true',loopbackHTTP:process.env.ALLOW_LOOPBACK_HTTP==='true'});
const timer=setInterval(()=>{void (async()=>{await app.engine.tick();await app.engine.reconcile();})().catch(()=>{});},15000);
app.server.listen(Number(process.env.PORT??8787),host,()=>console.log(`Luckin Random server ready (${mode}); real orders require all authorization gates.`));
for(const signal of ['SIGINT','SIGTERM'] as const)process.once(signal,()=>{clearInterval(timer);app.server.close(()=>{app.store.close();process.exit(0);});});
