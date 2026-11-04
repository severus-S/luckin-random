import JSONBig from 'json-bigint';
import { Ajv } from 'ajv';
import { Fault, cents, type Gateway, type Product, type Shop, type Preference, type Quote, type OrderStatus, type State } from './domain.js';

const parse = JSONBig({ storeAsString: true, protoAction: 'error', constructorAction: 'error' }).parse;
const ajv = new Ajv({ strict: false, allErrors: true });
export const officialEndpoint = 'https://gwmcp.lkcoffee.com/order/user/mcp';
type Tool = { name: string; inputSchema: Record<string, unknown> };
type Obj = Record<string, any>;
export class MCP {
  private id=0; private session?: string; private version='2025-03-26';
  private tools: Tool[]=[];
  constructor(private token: string, private endpoint=officialEndpoint, private fetcher: typeof fetch=fetch) {}
  async rpc(method: string, params: Obj, notification=false): Promise<any> {
    const id = notification ? undefined : ++this.id;
    const r=await this.fetcher(this.endpoint,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'Content-Type':'application/json','Accept':'application/json, text/event-stream','Authorization':`Bearer ${this.token}`,'MCP-Protocol-Version':this.version,...(this.session?{'Mcp-Session-Id':this.session}:{})},body:JSON.stringify({jsonrpc:'2.0',id,method,params})});
    if(r.status===401||r.status===403) throw new Fault('TOKEN_EXPIRED','瑞幸令牌已失效，请到官方平台重新授权',401);
    if(!r.ok) throw new Fault('MCP_HTTP',`瑞幸服务暂不可用（HTTP ${r.status}）`,502);
    const session=r.headers.get('mcp-session-id');if(session)this.session=session;
    if(notification){await r.body?.cancel();return;}
    let data:any;
    if(r.headers.get('content-type')?.includes('text/event-stream')) {
      const reader=r.body?.getReader();if(!reader)throw new Fault('MCP_PROTOCOL','瑞幸响应为空',502);
      const decoder=new TextDecoder();let buffer='',size=0;
      try {
        while(true){
          const next=await reader.read();if(next.done)break;
          size+=next.value.length;if(size>4_000_000)throw new Fault('MCP_PROTOCOL','瑞幸响应过大',502);
          buffer+=decoder.decode(next.value,{stream:true});buffer=buffer.replace(/\r\n/g,'\n');
          let end:number;
          while((end=buffer.indexOf('\n\n'))>=0){
            const event=buffer.slice(0,end);buffer=buffer.slice(end+2);
            const text=event.split('\n').filter(l=>l.startsWith('data:')).map(l=>l.slice(5).trimStart()).join('\n');
            if(!text)continue;const message=parse(text);if(message.id===id){data=message;break;}
          }
          if(data)break;
        }
      } finally { await reader.cancel().catch(()=>{}); }
    } else { const body=await r.text();if(body.length>4_000_000)throw new Fault('MCP_PROTOCOL','瑞幸响应过大',502);data=parse(body); }
    if(!data || data.id!==id || data.error)throw new Fault('MCP_PROTOCOL','瑞幸接口返回错误或结果不明，请查看验证记录',502);
    return data.result;
  }
  async discover(): Promise<Tool[]> {
    const init=await this.rpc('initialize',{protocolVersion:this.version,capabilities:{},clientInfo:{name:'LuckinRandom',version:'0.1.0'}});
    if(!['2024-11-05','2025-03-26','2025-06-18','2025-11-25'].includes(init.protocolVersion))throw new Fault('MCP_VERSION','瑞幸协议版本变化，需更新客户端');
    this.version=init.protocolVersion;await this.rpc('notifications/initialized',{},true);
    const list:Tool[]=[];let cursor: string|undefined;
    for(let n=0;n<20;n++){
      const page=await this.rpc('tools/list',cursor?{cursor}:{});
      if(!Array.isArray(page.tools))throw new Fault('SCHEMA','未返回工具 schema');list.push(...page.tools);cursor=page.nextCursor;if(!cursor)break;
      if(n===19)throw new Fault('SCHEMA','工具分页超出限制');
    }
    this.tools=list;return list;
  }
  async call(name: string, args: Obj) {
    if(!this.tools.length)await this.discover();
    const tool=this.tools.find(t=>t.name===name);if(!tool)throw new Fault('CAPABILITY',`官方未提供所需能力：${name}`);
    if(!ajv.validate(tool.inputSchema,args))throw new Fault('SCHEMA','参数与官方实时 schema 不匹配，已停止请求');
    const result=await this.rpc('tools/call',{name,arguments:args});
    if(result.isError)throw new Fault('UPSTREAM','瑞幸拒绝了请求，可能是缺货、规格、优惠券或门店不可用');
    let envelope=result.structuredContent;
    if(!envelope){const texts=result.content?.filter((c:Obj)=>c.type==='text').map((c:Obj)=>c.text);if(texts?.length===1)try{envelope=parse(texts[0]);}catch{}}
    if(!envelope || envelope.code!==0 || envelope.success!==true)throw new Fault('UPSTREAM','瑞幸未确认请求成功，已停止处理');
    return envelope.data;
  }
}
function str(v: unknown): string { if(typeof v==='string'&&v.length)return v;if(typeof v==='number'&&Number.isSafeInteger(v))return String(v);throw new Fault('CONTRACT','官方标识字段变化或精度不安全'); }
function integer(v: string): number { const n=Number(v);if(!/^\d+$/.test(v)||!Number.isSafeInteger(n))throw new Fault('CONTRACT','官方商品或门店标识不是安全整数');return n; }
function text(v: unknown): string { if(typeof v!=='string')throw new Fault('CONTRACT','官方文本字段变化');return v; }
function object(v: unknown): Obj { if(!v||typeof v!=='object'||Array.isArray(v))throw new Fault('CONTRACT','官方对象结构变化');return v as Obj; }
export function normalizeShop(v: unknown): Shop {
  const d=object(v);if(!Number.isFinite(d.longitude)||!Number.isFinite(d.latitude))throw new Fault('CONTRACT','门店坐标缺失');
  return {id:str(d.deptId),name:text(d.deptName),address:text(d.address),longitude:d.longitude,latitude:d.latitude,hours:`${text(d.workTimeStart)}–${text(d.workTimeEnd)}`};
}
export function normalizeProduct(v: unknown): Product {
  const d=object(v);if(!Array.isArray(d.productAttrs))throw new Fault('CONTRACT','商品规格结构变化');
  return {id:str(d.productId),name:text(d.productName),sku:text(d.skuCode),image:typeof d.pictureUrl==='string'?d.pictureUrl:undefined,category:'搜索结果',initialCents:cents(d.initialPrice),estimateCents:cents(d.estimatePrice),attributes:d.productAttrs.map((a:Obj)=>({id:integer(str(a.attributeId)),name:text(a.attributeName),options:a.productSubAttrs.map((o:Obj)=>({id:integer(str(o.attributeId)),name:text(o.attributeName),selected:o.selected===true,available:o.canSelected===1}))}))};
}
export function normalizeStatus(v: unknown): OrderStatus {
  const d=object(v), map:Record<number,State>={10:'awaitingPayment',20:'paid',30:'preparing',60:'ready',80:'completed',100:'cancelled'};
  const state=map[d.orderStatus]??'unknown';
  const code=d.takeMealCodeInfo?.code;
  return {state,payableCents:d.orderPayAmount===undefined?undefined:cents(d.orderPayAmount),pickupCode:['paid','preparing','ready','completed'].includes(state)&&typeof code==='string'&&code.length>0&&code!=='生成中'?code:undefined};
}
export function paymentQR(v: unknown): string|undefined {
  if(v===undefined||v===null||v==='')return;
  const s=text(v);let u:URL;try{u=new URL(s);}catch{throw new Fault('PAYMENT','付款二维码地址无效');}
  if(u.protocol!=='https:'||u.username||u.password||u.port||!(u.hostname==='lkcoffee.com'||u.hostname.endsWith('.lkcoffee.com')))throw new Fault('PAYMENT','付款二维码不是受支持的官方 HTTPS 地址');
  return s;
}
export class LiveGateway implements Gateway {
  readonly mode='live' as const;
  constructor(private mcp:MCP,private contractVerified=false){}
  async shops(longitude:number,latitude:number,query:string){const d=await this.mcp.call('queryShopList',{longitude,latitude,deptName:query});if(!Array.isArray(d))throw new Fault('CONTRACT','门店列表结构变化');return d.map(normalizeShop);}
  async search(s:Shop,query:string){if(!query.trim())throw new Fault('CAPABILITY','官方文档只证实商品搜索，尚未证实完整分类菜单；请输入饮品关键词');const d=await this.mcp.call('searchProductForMcp',{deptId:integer(s.id),query});if(!Array.isArray(d))throw new Fault('CONTRACT','商品搜索结构变化');return d.map(normalizeProduct);}
  async detail(s:Shop,id:string){return normalizeProduct(await this.mcp.call('queryProductDetailInfo',{deptId:integer(s.id),productId:integer(id)}));}
  async switch(s:Shop,p:Product,v:Preference){const g=p.attributes.find(a=>a.id===v.group);if(!g?.options.some(o=>o.id===v.option&&o.available))throw new Fault('SKU','保存的规格已不再可选');return normalizeProduct(await this.mcp.call('switchProduct',{deptId:integer(s.id),productId:integer(p.id),skuCode:p.sku,amount:1,attrOperationParam:{attributeId:v.group,subAttr:{attributeId:v.option,operation:3}}}));}
  async preview(shop:Shop,product:Product):Promise<Quote>{
    const d=object(await this.mcp.call('previewOrder',{deptId:integer(shop.id),productList:[{productId:integer(product.id),skuCode:product.sku,amount:1}]}));
    const line=d.productInfoList;
    if(!Array.isArray(line)||line.length!==1||str(line[0].productId)!==product.id||line[0].skuCode!==product.sku||line[0].amount!==1||str(d.shopInfo?.deptId)!==shop.id||!Array.isArray(d.couponCodeList)||d.couponCodeList.some((c:unknown)=>typeof c!=='string'))throw new Fault('CONTRACT','官方预览的门店、规格、数量或优惠结构与请求不符');
    return {shop,product,payableCents:cents(d.discountPrice),originalCents:cents(d.totalInitialPrice),coupons:d.couponCodeList,at:new Date().toISOString()};
  }
  async create(q:Quote,note:string){
    if(!this.contractVerified)throw new Fault('LIVE_UNVERIFIED','真实订单响应和支付尚未经验证，真实下单入口锁定',403);
    const d=object(await this.mcp.call('createOrder',{deptId:integer(q.shop.id),longitude:q.shop.longitude,latitude:q.shop.latitude,productList:[{productId:integer(q.product.id),skuCode:q.product.sku,amount:1}],couponCodeList:q.coupons,remark:note}));
    return {id:str(d.orderIdStr??d.orderId),qr:paymentQR(d.payOrderQrCodeUrl),payableCents:cents(d.discountPrice)};
  }
  async status(id:string){return normalizeStatus(await this.mcp.call('queryOrderDetailInfo',{orderId:id}));}
  async cancel(id:string){if(await this.mcp.call('cancelOrder',{orderId:id})!==true)throw new Fault('CANCEL','官方未确认取消成功');}
}
