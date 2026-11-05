import { createHash } from 'node:crypto';
import { choose, Fault, localParts, type Gateway, type Intent, type Limits, type Pool, type Shop, type Job, validateShop } from './domain.js';
import { Store } from './store.js';

// Single process owns the SQLite database. Durable unknown states survive restarts.
export class Engine {
  private busy=false;
  private reconciling=false;
  constructor(public store:Store, private gateway:()=>Gateway, private allowLive=false, private contractVerified=false, private now=()=>new Date(), private rng?:()=>number){}
  checkLive(g:Gateway){const c=this.store.config();if(g.mode==='live'&&(!this.allowLive||!this.contractVerified||!c.realOrdersEnabled||c.emergencyStop))throw new Fault('DISARMED','真实下单未授权或紧急停止已启用',403);}
  budget(price:number,limits:Limits,mode:'mock'|'live',exclude?:string,purpose:'spend'|'preview'='spend'){
    if(mode==='live'){
      const saved=this.store.secret('authorizedLimits');
      // Read-only previews never grant spending permission. Existing ceilings
      // still apply; every create path requires the saved authorization.
      if(!saved&&purpose==='spend')throw new Fault('AUTHORIZATION','尚未明确授权消费上限',403);
      if(saved){
        const ceiling=JSON.parse(saved) as Limits;limits={...limits};
        for(const k of ['cup','daily','weekly','monthly','dailyCount'] as const)limits[k]=Math.min(limits[k],ceiling[k]);
      }
    }
    if(!Number.isSafeInteger(price)||price<0)throw new Fault('PRICE','金额无效');
    if(price>limits.cup)throw new Fault('BUDGET','单杯价格超过上限');
    const now=localParts(this.now());let daily=0,weekly=0,monthly=0,count=0;
    for(const i of this.store.intents()){
      if(i.id===exclude||i.mode!==mode||!i.quote||['failed','cancelled','validating','previewed'].includes(i.state))continue;
      const d=localParts(new Date(i.createdAt)),n=i.quote.payableCents;
      if(d.day===now.day){daily+=n;count++;}if(d.week===now.week)weekly+=n;if(d.month===now.month)monthly+=n;
    }
    if(count>=limits.dailyCount)throw new Fault('DAILY_COUNT','已达到每日最多下单数量（含待支付及结果不明订单）');
    if(daily+price>limits.daily||weekly+price>limits.weekly||monthly+price>limits.monthly)throw new Fault('BUDGET','超过每日、每周或每月消费上限（含待支付预留金额）');
  }
  async run(id:string,poolId?:string,previewOnly=false,jobShop?:Shop,maxCents?:number,expectedJob?:Job):Promise<Intent>{
    if(!/^[A-Za-z0-9_-]{8,120}$/.test(id))throw new Fault('IDEMPOTENCY','幂等标识格式无效');
    const c=this.store.config(),pid=poolId??c.selectedPoolId;
    const fingerprint=createHash('sha256').update(JSON.stringify({pid,previewOnly,shop:jobShop?.id??c.shop?.id,maxCents})).digest('hex');
    const existing=this.store.get(id);
    if(existing){if(this.store.fingerprint(id)!==fingerprint)throw new Fault('IDEMPOTENCY_CONFLICT','同一幂等标识不能用于不同操作',409);return existing;}
    if(this.busy)throw new Fault('BUSY','已有点单正在处理，请勿重复触发',409);
    const g=this.gateway();if(!previewOnly)this.checkLive(g);
    if(!previewOnly&&this.store.intents().some(i=>i.mode===g.mode&&['unknown','creating','awaitingPayment'].includes(i.state)))throw new Fault('UNRESOLVED','存在待支付或结果不明订单，请先核对或取消',409);
    const pool=c.pools.find(p=>p.id===pid),shop=jobShop??c.shop;
    if(!pool||!shop)throw new Fault('SETUP','请先选择门店和咖啡池');validateShop(shop);
    const i:Intent={id,state:'validating',createdAt:this.now().toISOString(),mode:g.mode,poolId:pid,attempts:[]};
    this.busy=true;this.store.insert(i,fingerprint);
    try {
      const quote=await this.select(g,pool,shop,i,maxCents,previewOnly);i.quote=quote;
      if(previewOnly){i.state='previewed';this.store.save(i);return i;}
      // Re-read emergency stop, limits and authorization after all network awaits.
      this.checkLive(g);const latest=this.store.config();
      if(expectedJob&&JSON.stringify(this.store.jobs().find(j=>j.id===expectedJob.id))!==JSON.stringify(expectedJob))throw new Fault('JOB_CHANGED','任务在校验期间已暂停、删除或更改，已停止创建订单');
      if(!jobShop&&JSON.stringify(latest.shop)!==JSON.stringify(shop))throw new Fault('SHOP_CHANGED','常用门店在校验期间发生变化，请重新预览');
      if(JSON.stringify(latest.pools.find(p=>p.id===pid)?.candidates.find(v=>v.id===i.candidate?.id))!==JSON.stringify(i.candidate))throw new Fault('CONFIG_CHANGED','候选配置在预览期间改变，请重新发起');
      this.budget(quote.payableCents,latest.limits,g.mode,i.id);
      if(maxCents!==undefined&&quote.payableCents>maxCents)throw new Fault('BUDGET','超过任务授权金额');
      i.state='creating';this.store.save(i); // durable reservation BEFORE mutation
      try {
        const made=await g.create(quote,i.candidate!.note);
        i.officialOrderId=made.id;i.paymentQRURL=made.qr;
        if(made.payableCents!==quote.payableCents){i.state='unknown';i.reason='创建订单金额与预览不一致，已停止付款引导，请核对官方订单';}
        else i.state='awaitingPayment';
      }catch{ i.state='unknown';i.reason='订单创建结果不明；禁止再次下单，请核对瑞幸官方订单。无官方订单 ID 时无法自动恢复'; }
      this.store.save(i);this.store.notify(i.state==='unknown'?i.reason!:`${i.mode==='mock'?'模拟 · ':''}${i.candidate!.name} 已创建，请打开 App 查看付款信息`);return i;
    }catch(e){i.state='failed';i.reason=e instanceof Fault?e.message:'服务连接失败，未继续创建订单';this.store.save(i);this.store.notify(i.reason);return i;}
    finally{this.busy=false;}
  }
  private async select(g:Gateway,p:Pool,s:Shop,i:Intent,max?:number,previewOnly=false){
    const previous=this.store.intents().find(v=>v.id!==i.id&&v.mode===g.mode&&v.poolId===p.id&&v.officialOrderId)?.candidate?.id;
    let remaining=p.candidates.filter(c=>c.enabled);
    const reasons:string[]=[];
    while(remaining.length){
      const candidate=choose(remaining,p.weighted,previous,p.avoidRepeat,this.rng);
      remaining=remaining.filter(c=>c.id!==candidate.id);i.candidate=candidate;
      try{
        let product=await g.detail(s,candidate.productId);
        for(const pref of candidate.preferences)product=await g.switch(s,product,pref);
        for(const pref of candidate.preferences)if(!product.attributes.find(a=>a.id===pref.group)?.options.some(o=>o.id===pref.option&&o.selected))throw new Fault('SKU','规格切换结果与保存的偏好不一致');
        if(product.id!==candidate.productId)throw new Fault('SKU','官方返回了其他商品，已停止');
        const quote=await g.preview(s,product);this.budget(quote.payableCents,this.store.config().limits,g.mode,i.id,previewOnly?'preview':'spend');
        if(max!==undefined&&quote.payableCents>max)throw new Fault('BUDGET','超过任务授权金额');
        i.attempts.push({candidateId:candidate.id,reason:'官方预览通过'});return quote;
      }catch(e){
        if(!(e instanceof Fault)||['TOKEN_EXPIRED','MCP_HTTP','MCP_PROTOCOL','CONTRACT','SCHEMA','DAILY_COUNT'].includes(e.code))throw e;
        reasons.push(`${candidate.name}：${e.message}`);i.attempts.push({candidateId:candidate.id,reason:e.message});
      }
    }
    throw new Fault('NO_CANDIDATE',reasons.join('；')||'咖啡池中没有启用的饮品');
  }
  async refresh(id:string):Promise<Intent>{
    const i=this.store.get(id);if(!i)throw new Fault('NOT_FOUND','订单不存在',404);
    const g=this.gateway();if(g.mode!==i.mode)throw new Fault('MODE','请切回订单对应的服务模式');
    if(!i.officialOrderId){if(i.state==='unknown')throw new Fault('UNKNOWN','缺少官方订单 ID，无法安全查询；请人工核对，禁止重新创建');return i;}
    const status=await g.status(i.officialOrderId);
    if(['paid','preparing','ready','completed'].includes(i.state)&&['awaitingPayment','failed'].includes(status.state))throw new Fault('STATE','官方返回了倒退的支付状态，请稍后再次查询');
    const was=i.state,before=JSON.stringify(i);i.state=status.state;i.pickupCode=status.pickupCode;
    if(i.state!=='unknown')i.reason=undefined;
    if(status.payableCents!==undefined&&i.quote&&status.payableCents!==i.quote.payableCents){i.state='unknown';i.reason='官方订单金额发生变化，请核对';}
    if(before!==JSON.stringify(i))this.store.save(i);if(was!==i.state)this.store.notify(`订单状态：${i.state}`);return i;
  }
  async cancel(id:string){const i=await this.refresh(id);if(i.state!=='awaitingPayment'||!i.officialOrderId)throw new Fault('CANCEL','仅可尝试取消官方确认的待付款订单');
    try{await this.gateway().cancel(i.officialOrderId);return await this.refresh(id);}catch{ i.state='unknown';i.reason='取消结果不明，请查询官方订单，不要重新下单';this.store.save(i);return i; }
  }
  async tick(at=this.now()){
    const c=this.store.config();if(c.emergencyStop)return;
    for(const j of this.store.jobs()){
      if(!j.enabled||!j.authorized)continue;
      const p=localParts(at,j.timezone);if(!j.weekdays.includes(p.weekday)||p.hour!==j.hour||p.minute!==j.minute)continue;
      const slot=`${p.day}T${String(p.hour).padStart(2,'0')}:${String(p.minute).padStart(2,'0')}`;
      const id=`job_${createHash('sha256').update(j.id+slot).digest('hex')}`;
      if(!this.store.claim(j.id,slot,id))continue;
      try{await this.run(id,j.poolId,false,j.shop,j.maxCents,j);}catch(e){this.store.notify(e instanceof Fault?e.message:'定时任务未完成，请检查执行记录');}
    }
  }
  async reconcile(){
    if(this.reconciling||this.busy)return;this.reconciling=true;
    try{
      const mode=this.gateway().mode;
      for(const i of this.store.intents().filter(v=>v.mode===mode&&v.officialOrderId&&['awaitingPayment','paid','preparing','ready','unknown'].includes(v.state)).slice(0,20)){
        try{await this.refresh(i.id);}catch(e){if(e instanceof Fault&&e.code==='TOKEN_EXPIRED')break;}
      }
    }finally{this.reconciling=false;}
  }
}
export function validateJob(j:Job,store:Store){
  if(!j||!/^[A-Za-z0-9_-]{8,120}$/.test(j.id)||typeof j.enabled!=='boolean'||typeof j.authorized!=='boolean'||!Number.isInteger(j.hour)||j.hour<0||j.hour>23||!Number.isInteger(j.minute)||j.minute<0||j.minute>59||!Array.isArray(j.weekdays)||!j.weekdays.length||j.weekdays.some(d=>!Number.isInteger(d)||d<0||d>6)||!Number.isSafeInteger(j.maxCents)||j.maxCents<1||!store.config().pools.some(p=>p.id===j.poolId))throw new Fault('JOB','任务配置无效');
  try{localParts(new Date(),j.timezone);}catch{throw new Fault('TIMEZONE','时区无效');}validateShop(j.shop);
}
