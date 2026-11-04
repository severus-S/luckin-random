import { createMockMCP } from './mock-mcp.js';
const {server}=createMockMCP();
server.listen(8790,'127.0.0.1',()=>console.log('SYNTHETIC Mock MCP: http://127.0.0.1:8790/mcp; no real account, orders or payments.'));
