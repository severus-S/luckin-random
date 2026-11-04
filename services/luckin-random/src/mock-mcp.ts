import { createServer } from 'node:http';
import { MockGateway } from './mock.js';
import { Fault, type Product, type Shop } from './domain.js';

// Synthetic schemas for testing the transport, NOT a captured tools/list response.
const properties={deptId:{type:'integer'},longitude:{type:'number'},latitude:{type:'number'},deptName:{type:'string'},query:{type:'string'},productId:{type:'integer'},skuCode:{type:'string'},amount:{type:'integer'},orderId:{type:'string'},remark:{type:'string'},couponCodeList:{type:'array',items:{type:'string'}},attrOperationParam:{type:'object',properties:{attributeId:{type:'integer'},subAttr:{type:'object',properties:{attributeId:{type:'integer'},operation:{const:3}},required:['attributeId','operation']}},required:['attributeId','subAttr']},productList:{type:'array',minItems:1,maxItems:1,items:{type:'object',properties:{productId:{type:'integer'},skuCode:{type:'string'},amount:{const:1}},required:['productId','skuCode','amount']}}};
const definitions:Record<string,{keys:string[];required:string[]}>= {
 queryShopList:{keys:['deptId','longitude','latitude','deptName'],required:['longitude','latitude']},
 searchProductForMcp:{keys:['deptId','query'],required:['deptId','query']},
 queryProductDetailInfo:{keys:['deptId','productId'],required:['deptId','productId']},
 switchProduct:{keys:['deptId','productId','skuCode','amount','attrOperationParam'],required:['deptId','productId','skuCode','amount','attrOperationParam']},
 previewOrder:{keys:['deptId','productList'],required:['deptId','productList']},
 createOrder:{keys:['deptId','longitude','latitude','productList','couponCodeList','remark'],required:['deptId','longitude','latitude','productList']},
 queryOrderDetailInfo:{keys:['orderId'],required:['orderId']},cancelOrder:{keys:['orderId'],required:['orderId']}
};
const rawShop=(s:Shop)=>({deptId:Number(s.id),deptName:s.name,address:s.address,longitude:s.longitude,latitude:s.latitude,workTimeStart:'00:00',workTimeEnd:'24:00'});
const rawProduct=(p:Product)=>({productId:Number(p.id),productName:p.name,skuCode:p.sku,pictureUrl:p.image??'',initialPrice:p.initialCents/100,estimatePrice:p.estimateCents/100,productAttrs:p.attributes.map(a=>({attributeId:a.id,attributeName:a.name,productSubAttrs:a.options.map(o=>({attributeId:o.id,attributeName:o.name,selected:o.selected,canSelected:o.available?1:0,price:0}))}))});
export function createMockMCP(){
 const gateway=new MockGateway(),configured=new Map<string,Product>();let id=0;
 const server=createServer(async(req,res)=>{
  if(req.method!=='POST'||req.url!=='/mcp'){res.writeHead(404);res.end();return;}
  let body='';for await(const chunk of req){body+=chunk.toString();if(body.length>100000){res.writeHead(413);res.end();return;}}
  let rpc:any;
  try{
   rpc=JSON.parse(body);
   if(rpc.method==='notifications/initialized'){res.writeHead(202);res.end();return;}
   let result:unknown;
   if(rpc.method==='initialize')result={protocolVersion:'2025-03-26',capabilities:{tools:{}},serverInfo:{name:'LuckinRandom-MOCK-NO-REAL-ORDERS',version:'0.1.0'}};
   else if(rpc.method==='tools/list')result={tools:Object.entries(definitions).map(([name,d])=>({name,description:'SYNTHETIC MOCK ONLY',inputSchema:{type:'object',properties:Object.fromEntries(d.keys.map(k=>[k,properties[k as keyof typeof properties]])),required:d.required,additionalProperties:false}}))};
   else if(rpc.method==='tools/call'){
    const {name,arguments:a}=rpc.params;let data:unknown;
    if(name==='queryShopList')data=(await gateway.shops()).map(rawShop);
    else if(name==='searchProductForMcp')data=(await gateway.search(gateway.shop,a.query)).map(rawProduct);
    else if(name==='queryProductDetailInfo')data=rawProduct(await gateway.detail(gateway.shop,String(a.productId)));
    else if(name==='switchProduct'){
     const p=configured.get(a.skuCode)??await gateway.detail(gateway.shop,String(a.productId));
     const out=await gateway.switch(gateway.shop,p,{group:a.attrOperationParam.attributeId,option:a.attrOperationParam.subAttr.attributeId,label:'mock'});configured.set(out.sku,out);data=rawProduct(out);
    }else if(name==='previewOrder'||name==='createOrder'){
     const l=a.productList[0],p=configured.get(l.skuCode)??await gateway.detail(gateway.shop,String(l.productId));
     const q=await gateway.preview(gateway.shop,{...p,sku:l.skuCode});
     if(name==='previewOrder')data={discountPrice:q.payableCents/100,totalInitialPrice:q.originalCents/100,couponCodeList:q.coupons,shopInfo:rawShop(q.shop),productInfoList:[{productId:Number(p.id),skuCode:l.skuCode,amount:1}]};
     else{const out=await gateway.create(q);data={orderIdStr:out.id,discountPrice:out.payableCents/100,needPay:true};}
    }else if(name==='queryOrderDetailInfo'){
     const s=await gateway.status(a.orderId);const map:Record<string,number>={awaitingPayment:10,paid:20,preparing:30,ready:60,completed:80,cancelled:100};data={orderId:a.orderId,orderStatus:map[s.state]??999,orderPayAmount:(s.payableCents??990)/100,takeMealCodeInfo:{code:s.pickupCode??'生成中'}};
    }else if(name==='cancelOrder'){await gateway.cancel(a.orderId);data=true;}
    else throw new Fault('UNKNOWN','Unknown mock tool');
    result={content:[{type:'text',text:JSON.stringify({code:0,success:true,data})}]};
   }else throw new Fault('UNKNOWN','Unknown mock method');
   res.writeHead(200,{'Content-Type':'text/event-stream','Mcp-Session-Id':'MOCK-SESSION'});
   res.end(`id: ${++id}\nevent: message\ndata: ${JSON.stringify({jsonrpc:'2.0',id:rpc.id,result})}\n\n`);
  }catch{
   res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({jsonrpc:'2.0',id:rpc?.id??null,result:{isError:true,content:[{type:'text',text:'Mock rejected request'}]}}));
  }
 });return{server,gateway};
}
