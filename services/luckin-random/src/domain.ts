import { randomInt, randomUUID } from 'node:crypto';

export class Fault extends Error {
  constructor(public code: string, message: string, public status = 422) { super(message); }
}
export interface Option { id: number; name: string; selected: boolean; available: boolean }
export interface Attribute { id: number; name: string; options: Option[] }
export interface Product {
  id: string; name: string; sku: string; image?: string; category: string;
  attributes: Attribute[]; initialCents: number; estimateCents: number;
}
export interface Shop { id: string; name: string; address: string; longitude: number; latitude: number; hours: string }
export interface Preference { group: number; option: number; label: string }
export interface Candidate {
  id: string; productId: string; name: string; sku: string;
  preferences: Preference[]; note: string; weight: number; enabled: boolean;
}
export interface Pool { id: string; name: string; candidates: Candidate[]; weighted: boolean; avoidRepeat: boolean }
export interface Limits { cup: number; daily: number; weekly: number; monthly: number; dailyCount: number }
export interface Configuration {
  schemaVersion: 1; pools: Pool[]; selectedPoolId: string; shop: Shop | null;
  limits: Limits; realOrdersEnabled: boolean; emergencyStop: boolean;
  paymentPreference: 'alipay' | 'wechat';
}
export const defaults = (): Configuration => {
  const id = randomUUID();
  return { schemaVersion: 1, pools: [{ id, name: '我的咖啡池', candidates: [], weighted: false, avoidRepeat: true }],
    selectedPoolId: id, shop: null, limits: { cup: 2000, daily: 2000, weekly: 10000, monthly: 30000, dailyCount: 1 },
    realOrdersEnabled: false, emergencyStop: true, paymentPreference: 'alipay' };
};
export interface Quote { product: Product; shop: Shop; payableCents: number; originalCents: number; coupons: string[]; at: string }
export type State = 'validating' | 'previewed' | 'creating' | 'awaitingPayment' | 'paid' | 'preparing' | 'ready' | 'completed' | 'cancelled' | 'unknown' | 'failed';
export interface Intent {
  id: string; state: State; createdAt: string; mode: 'mock' | 'live'; poolId: string;
  candidate?: Candidate; quote?: Quote; officialOrderId?: string; paymentQRURL?: string;
  pickupCode?: string; reason?: string; attempts: { candidateId: string; reason: string }[];
}
export interface OrderStatus { state: State; pickupCode?: string; payableCents?: number }
export interface Gateway {
  readonly mode: 'mock' | 'live';
  shops(longitude: number, latitude: number, query: string): Promise<Shop[]>;
  search(shop: Shop, query: string): Promise<Product[]>;
  detail(shop: Shop, id: string): Promise<Product>;
  switch(shop: Shop, product: Product, pref: Preference): Promise<Product>;
  preview(shop: Shop, product: Product): Promise<Quote>;
  create(quote: Quote, note: string): Promise<{ id: string; qr?: string; payableCents: number }>;
  status(id: string): Promise<OrderStatus>;
  cancel(id: string): Promise<void>;
}
export interface Job {
  id: string; enabled: boolean; authorized: boolean; poolId: string; shop: Shop;
  hour: number; minute: number; weekdays: number[]; timezone: string; maxCents: number;
}

export function choose(candidates: Candidate[], weighted: boolean, previous?: string, avoid = false, rng = () => randomInt(0, 2 ** 32) / 2 ** 32): Candidate {
  let list = candidates.filter(c => c.enabled);
  if (avoid && list.length > 1) list = list.filter(c => c.id !== previous);
  if (!list.length) throw new Fault('EMPTY_POOL', '没有启用的候选饮品，请先添加饮品');
  const weights = list.map(c => weighted ? c.weight : 1);
  if (weights.some(w => !Number.isFinite(w) || w <= 0 || w > 10000)) throw new Fault('WEIGHT', '随机权重必须在 0 到 10000 之间');
  let ticket = rng() * weights.reduce((a, b) => a + b, 0);
  for (let i = 0; i < list.length; i++) { ticket -= weights[i]!; if (ticket < 0) return list[i]!; }
  return list[list.length - 1]!;
}
export const cents = (value: unknown): number => {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1_000_000) throw new Fault('CONTRACT', '官方金额格式变化，已停止处理');
  return Math.round(value * 100);
};
export function localParts(date: Date, zone = 'Asia/Shanghai') {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(date);
  const p = Object.fromEntries(parts.map(v => [v.type, v.value]));
  const day = `${p.year}-${p.month}-${p.day}`;
  const d = new Date(`${day}T00:00:00Z`), weekday = d.getUTCDay();
  d.setUTCDate(d.getUTCDate() - (weekday + 6) % 7);
  return { day, month: day.slice(0, 7), week: d.toISOString().slice(0, 10), weekday, hour: Number(p.hour), minute: Number(p.minute) };
}
export function validateConfiguration(c: Configuration): void {
  if (!c || c.schemaVersion !== 1 || !Array.isArray(c.pools) || c.pools.length < 1 || c.pools.length > 30) throw new Fault('CONFIG', '配置版本或咖啡池数量无效');
  const ids = new Set<string>();
  for (const p of c.pools) {
    if (!p.id || ids.has(p.id) || typeof p.name !== 'string' || p.name.length > 80 || !Array.isArray(p.candidates) || p.candidates.length > 200 || typeof p.weighted !== 'boolean' || typeof p.avoidRepeat !== 'boolean') throw new Fault('CONFIG', '咖啡池配置无效');
    ids.add(p.id); const ci = new Set<string>();
    for (const v of p.candidates) {
      if (typeof v.id !== 'string' || !v.id || ci.has(v.id) || typeof v.name !== 'string' || typeof v.productId !== 'string' || !v.productId || typeof v.sku !== 'string' || !v.sku || !Number.isFinite(v.weight) || v.weight <= 0 || v.weight > 10000 || typeof v.enabled !== 'boolean' || typeof v.note !== 'string' || v.note.length > 200 || !Array.isArray(v.preferences) || v.preferences.some(a => !Number.isSafeInteger(a.group) || !Number.isSafeInteger(a.option) || typeof a.label !== 'string')) throw new Fault('CONFIG', '候选饮品配置无效');
      ci.add(v.id);
    }
  }
  if (!ids.has(c.selectedPoolId) || !c.limits || (['cup','daily','weekly','monthly','dailyCount'] as const).some(k => !Number.isSafeInteger(c.limits[k]) || c.limits[k] < 0 || c.limits[k] > 100_000_000) || c.limits.dailyCount < 1 || c.limits.dailyCount > 20 || c.limits.cup < 1 || typeof c.realOrdersEnabled !== 'boolean' || typeof c.emergencyStop !== 'boolean' || !['alipay','wechat'].includes(c.paymentPreference)) throw new Fault('CONFIG', '消费限制或授权设置无效');
  if (c.shop) validateShop(c.shop);
}
export function validateShop(s: Shop) {
  if (!s || typeof s.id !== 'string' || !/^\d+$/.test(s.id) || typeof s.name !== 'string' || !Number.isFinite(s.latitude) || Math.abs(s.latitude) > 90 || !Number.isFinite(s.longitude) || Math.abs(s.longitude) > 180) throw new Fault('SHOP', '门店信息无效，请重新选择');
}
