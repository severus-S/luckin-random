import { mkdirSync, writeFileSync } from 'node:fs';
import { MCP } from './mcp.js';

// This command calls only initialize / notifications/initialized / tools/list.
const token=process.env.LUCKIN_MCP_TOKEN;
if(!token){console.error('Set LUCKIN_MCP_TOKEN locally; never paste it into logs or commit it.');process.exit(1);}
try{
  const tools=await new MCP(token).discover();mkdirSync('../../artifacts/luckin-research',{recursive:true});
  writeFileSync('../../artifacts/luckin-research/tools.schema.json',JSON.stringify({source:'authenticated tools/list',verifiedAt:new Date().toISOString(),tools},null,2));
  console.log(JSON.stringify({verified:true,tools:tools.map(t=>t.name)}));
}catch{console.error('Authenticated schema discovery failed; token expired or endpoint unavailable. No orders were created.');process.exitCode=1;}
