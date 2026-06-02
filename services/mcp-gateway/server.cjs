// MCP Gateway - STUB (미구현 자리표시)
// 실제 구현 시 아래 엔드포인트를 채운다:
//   POST /mcp/document.parse, /mcp/document.chunk, /mcp/embedding.create,
//        /mcp/vector.upsert, /mcp/vector.search, /mcp/vector.delete,
//        /mcp/web.extract_main_content, /mcp/llm.call,
//        /mcp/storage.download, /mcp/storage.upload, /mcp/security.mask_pii
const http = require("http");
const PORT = process.env.PORT || 8088;
const TOOLS = [
  "document.parse", "document.chunk", "embedding.create",
  "vector.upsert", "vector.search", "vector.delete",
  "web.fetch", "web.extract_main_content", "llm.call",
  "storage.download", "storage.upload", "security.mask_pii",
];
const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ status: "ok", role: "mcp-gateway", state: "stub", tools: TOOLS }));
  }
  if (req.method === "POST" && req.url.startsWith("/mcp/")) {
    const tool = req.url.replace("/mcp/", "");
    res.writeHead(501, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ error: "NOT_IMPLEMENTED", tool, message: "MCP Gateway stub - implement this tool" }));
  }
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
});
server.listen(PORT, () => console.log(`[mcp-gateway:stub] listening on :${PORT}`));
