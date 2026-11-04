import { Fault, type Gateway, type Product, type Shop, type Preference, type Quote, type OrderStatus } from './domain.js';

// These deliberately synthetic identifiers never enter the live adapter.
export class MockGateway implements Gateway {
  readonly mode = 'mock' as const;
  calls = 0; expired = false; couponExpired = false; createTimeout = false;
  invalid = new Set<string>(); price = 990;
  orders = new Map<string, OrderStatus>();
  shop: Shop = { id:'900001',name:'模拟门店 · 不产生消费',address:'测试数据，非真实门店',longitude:116.4,latitude:39.9,hours:'00:00–24:00' };
  products: Product[] = ['模拟椰香拿铁','模拟醇厚拿铁','模拟果香美式'].map((name,i) => ({id:String(900101+i),name,sku:`MOCK-${i}-cold`,category:i===2?'美式':'拿铁',initialCents:1800,estimateCents:990,attributes:[{id:1,name:'温度',options:[{id:11,name:'冰',selected:true,available:true},{id:12,name:'热',selected:false,available:true}]},{id:2,name:'糖度',options:[{id:21,name:'标准',selected:true,available:true},{id:22,name:'少糖',selected:false,available:true}]}]}));
  check() { if(this.expired) throw new Fault('TOKEN_EXPIRED','瑞幸授权已失效，请重新授权',401); }
  async shops(): Promise<Shop[]> { this.check();return [structuredClone(this.shop)]; }
  async search(_s: Shop,q: string) { this.check(); return structuredClone(this.products.filter(p=>p.name.includes(q)||q==='')); }
  async detail(_s: Shop,id: string) { this.check();const p=this.products.find(p=>p.id===id); if(!p || this.invalid.has(id)) throw new Fault('UNAVAILABLE','饮品已停售或缺货');return structuredClone(p); }
  async switch(_s: Shop,p: Product,v: Preference) { const out=structuredClone(p), group=out.attributes.find(a=>a.id===v.group); if(!group?.options.some(o=>o.id===v.option&&o.available)) throw new Fault('SKU','保存的规格已不可选'); group.options.forEach(o=>o.selected=o.id===v.option);out.sku=`MOCK-${p.id}-${out.attributes.flatMap(a=>a.options.filter(o=>o.selected).map(o=>o.id)).join('-')}`;return out; }
  async preview(shop: Shop,product: Product): Promise<Quote> { this.check(); if(this.couponExpired) throw new Fault('COUPON_EXPIRED','优惠券已失效，请重新预览'); return {shop,product,payableCents:this.price,originalCents:1800,coupons:['MOCK-COUPON'],at:new Date().toISOString()}; }
  async create(q: Quote) { this.calls++;const id=`MOCK-ORDER-${this.calls}`;this.orders.set(id,{state:'awaitingPayment',payableCents:q.payableCents}); if(this.createTimeout) throw new Fault('TIMEOUT','模拟订单创建超时');return {id,payableCents:q.payableCents}; }
  async status(id: string) { this.check(); const s=this.orders.get(id); if(!s) throw new Fault('NOT_FOUND','模拟服务重启后订单已过期',404);return s; }
  async cancel(id: string) { const s=await this.status(id);if(s.state!=='awaitingPayment') throw new Fault('CANCEL','仅允许取消未支付订单');this.orders.set(id,{state:'cancelled'}); }
  simulate(id: string,state: 'paid'|'failed'|'ready') { if(!this.orders.has(id)) throw new Fault('NOT_FOUND','模拟订单不存在',404);this.orders.set(id,{state,pickupCode:state==='ready'?'MOCK-A001':undefined}); }
}
