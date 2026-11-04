import { createServer, type ServerResponse } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { Fault, validateConfiguration } from './domain.js';
import { Engine, validateJob } from './engine.js';
import { Store } from './store.js';
import { LiveGateway, MCP } from './mcp.js';
import { MockGateway } from './mock.js';

export interface ServerOptions { key:string; encryptionKey:Buffer; database:string; mode:'mock'|'live'; allowLive?:boolean; contractVerified?:boolean; loopbackHTTP?:boolean }
export function application(o:ServerOptions){
  if(o.key.length<32)throw new Error('API_KEY requires at least 32 characters');
  const store=new Store(o.database,o.encryptionKey),mock=new MockGateway();
  const gateway=()=>{
    if(o.mode==='mock')return mock;
    const token=store.secret('mcp');if(!token)throw new Fault('TOKEN_REQUIRED','请先在官方平台授权，再在设置中安全保存令牌',401);
    return new LiveGateway(new MCP(token),o.contractVerified);
  };
  const engine=new Engine(store,gateway,o.allowLive,o.contractVerified);
  const buckets=new Map<string,{at:number;count:number}>();
  const send=(res:ServerResponse,status:number,data:unknown)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});res.end(JSON.stringify(data));};
  const server=createServer(async(req,res)=>{
    try{
      const ip=req.socket.remoteAddress??'',local=['127.0.0.1','::1','::ffff:127.0.0.1'].includes(ip);
      // TLS is terminated by a local reverse proxy; it must overwrite X-Forwarded-Proto.
      if(!(local&&o.loopbackHTTP)&&!(local&&req.headers['x-forwarded-proto']==='https'))throw new Fault('HTTPS','需要通过 HTTPS 访问',403);
      if(req.headers.origin)throw new Fault('ORIGIN','不接受浏览器跨站请求',403);
      const now=Date.now(),b=buckets.get(ip);if(!b||now-b.at>60000)buckets.set(ip,{at:now,count:1});else if(++b.count>120)throw new Fault('RATE_LIMIT','请求过于频繁，请稍后再试',429);
      const actual=Buffer.from(req.headers.authorization??''),expected=Buffer.from(`Bearer ${o.key}`);
      if(actual.length!==expected.length||!timingSafeEqual(actual,expected))throw new Fault('AUTH','后端配对密钥无效',401);
      const u=new URL(req.url??'/','http://localhost'),path=u.pathname,method=req.method;
      const body=async()=>{let s='';for await(const chunk of req){s+=chunk.toString();if(Buffer.byteLength(s)>1024*1024)throw new Fault('BODY','请求内容过大',413);}try{return JSON.parse(s||'{}');}catch{throw new Fault('JSON','请求格式无效',400);}};
      let result:unknown;
      if(method==='GET'&&path==='/v1/status')result={mode:o.mode,liveOrdersAvailable:!!(o.allowLive&&o.contractVerified),hasToken:!!store.secret('mcp'),schemaVersion:1,notificationDelivery:'in-app inbox; remote push unavailable',menuCapability:'search-only-until-verified'};
      else if(method==='GET'&&path==='/v1/config')result=store.config();
      else if(method==='PUT'&&path==='/v1/config'){
        const b=await body();validateConfiguration(b);
        // Configuration sync/restore must never re-arm an emergency-stopped server.
        const current=store.config();b.realOrdersEnabled=current.realOrdersEnabled;b.emergencyStop=current.emergencyStop;
        store.setConfig(b);result=b;
      }
      else if(method==='POST'&&path==='/v1/authorization'){
        const b=await body();
        if(b.confirmation!=='AUTHORIZE_WITH_SAVED_LIMITS'||typeof b.enableRealOrders!=='boolean'||typeof b.resumeTasks!=='boolean')throw new Fault('AUTHORIZATION','需要明确的下单与任务授权',403);
        if(b.enableRealOrders&&!(o.allowLive&&o.contractVerified))throw new Fault('DISARMED','真实接口尚未经验证，无法启用真实下单',403);
        if(b.enableRealOrders){
          if(b.authorizeLimits===true)store.secret('authorizedLimits',JSON.stringify(store.config().limits));
          else if(!store.secret('authorizedLimits'))throw new Fault('AUTHORIZATION','必须明确授权当前消费上限',403);
        }
        const c=store.config();c.realOrdersEnabled=b.enableRealOrders;c.emergencyStop=!b.resumeTasks;store.setConfig(c);result=c;
      }
      else if(method==='POST'&&path==='/v1/token'){
        const b=await body();if(typeof b.token!=='string'||b.token.length<20||b.token.length>16000)throw new Fault('TOKEN','令牌格式无效');
        // Verification is read-only. Never persist an invalid token.
        const tools=await new MCP(b.token).discover();store.secret('mcp',b.token);result={verified:true,tools:tools.map(t=>t.name)};
      }
      else if(method==='DELETE'&&path==='/v1/token'){store.revoke();result={revokedLocally:true,message:'已删除服务端令牌并停止自动下单；还需在瑞幸官方平台撤销令牌'};}
      else if(method==='GET'&&path==='/v1/shops'){
        const lon=Number(u.searchParams.get('longitude')),lat=Number(u.searchParams.get('latitude'));
        if(!u.searchParams.has('longitude')||!u.searchParams.has('latitude')||!Number.isFinite(lon)||Math.abs(lon)>180||!Number.isFinite(lat)||Math.abs(lat)>90)throw new Fault('COORDINATES','请输入准确的 GCJ-02 经纬度');
        result=await gateway().shops(lon,lat,u.searchParams.get('query')??'');
      }
      else if(method==='GET'&&path==='/v1/products'){
        const s=store.config().shop;if(!s)throw new Fault('SHOP','请先选择常用门店');result=await gateway().search(s,u.searchParams.get('query')??'');
      }
      else if(method==='POST'&&path==='/v1/product-detail'){
        const s=store.config().shop;if(!s)throw new Fault('SHOP','请先选择常用门店');const b=await body();
        if(typeof b.id!=='string')throw new Fault('PRODUCT','商品标识无效');let p=await gateway().detail(s,b.id);
        const prefs=b.preferences??(b.preference?[b.preference]:[]);
        if(!Array.isArray(prefs)||prefs.length>30)throw new Fault('SKU','规格无效');
        for(const v of prefs){if(!Number.isSafeInteger(v.group)||!Number.isSafeInteger(v.option))throw new Fault('SKU','规格无效');p=await gateway().switch(s,p,v);}
        result=p;
      }
      else if(method==='POST'&&path==='/v1/orders'){
        const b=await body();if(typeof b.previewOnly!=='boolean'||typeof b.id!=='string'||(b.poolId!==undefined&&typeof b.poolId!=='string'))throw new Fault('ORDER','点单参数无效');result=await engine.run(b.id,b.poolId,b.previewOnly);
      }
      else if(method==='GET'&&path==='/v1/orders')result=store.intents();
      else if(method==='POST'&&/^\/v1\/orders\/[^/]+\/refresh$/.test(path))result=await engine.refresh(path.split('/')[3]!);
      else if(method==='POST'&&/^\/v1\/orders\/[^/]+\/cancel$/.test(path))result=await engine.cancel(path.split('/')[3]!);
      else if(method==='POST'&&/^\/v1\/orders\/[^/]+\/simulate$/.test(path)){
        if(o.mode!=='mock')throw new Fault('MOCK_ONLY','仅可在模拟模式使用',403);
        const i=store.get(path.split('/')[3]!),b=await body();if(!i?.officialOrderId||!['paid','failed','ready'].includes(b.state))throw new Fault('MOCK','模拟参数无效');mock.simulate(i.officialOrderId,b.state);result=await engine.refresh(i.id);
      }
      else if(method==='GET'&&path==='/v1/jobs')result=store.jobs();
      else if(method==='PUT'&&path==='/v1/jobs'){const j=await body();validateJob(j,store);if(j.enabled&&!j.authorized)throw new Fault('JOB_AUTH','启用前必须明确授权自动任务');store.job(j);result=j;}
      else if(method==='DELETE'&&/^\/v1\/jobs\/[^/]+$/.test(path)){store.deleteJob(path.split('/')[3]!);result={deleted:true};}
      else if(method==='POST'&&path==='/v1/emergency-stop'){const c=store.config();c.emergencyStop=true;c.realOrdersEnabled=false;store.setConfig(c);result=c;}
      else if(method==='GET'&&path==='/v1/job-runs')result=store.runs();
      else if(method==='GET'&&path==='/v1/events')result=store.events();
      else if(method==='GET'&&path==='/v1/notifications')result=store.notifications();
      else throw new Fault('NOT_FOUND','接口不存在',404);
      send(res,200,result);
    }catch(e){const f=e instanceof Fault?e:new Fault('INTERNAL','服务请求未完成，请检查连接和验证记录',500);send(res,f.status,{code:f.code,message:f.message});}
  });
  server.requestTimeout=30000;server.headersTimeout=10000;server.maxHeadersCount=40;
  return {server,store,engine,mock};
}
