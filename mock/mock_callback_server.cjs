// =====================================================================
// Mock Base44 Callback Receiver
// ---------------------------------------------------------------------
// Base44가 아직 없을 때 n8n workflow의 success/failed callback을 수신하여
// 콘솔 출력 + ./logs/callbacks.log(JSONL) 에 저장한다.
// 의존성 없음(Node 표준 http 모듈). Node 18+ 권장.
//
// 실행:  node mock_callback_server.js   (기본 포트 4000)
//        PORT=4100 node mock_callback_server.js
// 엔드포인트:
//   POST /mock-callback   <- workflow callback 수신
//   GET  /callbacks       <- 최근 수신 내역 조회(JSON)
//   GET  /health          <- 헬스체크
// =====================================================================
const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = process.env.PORT || 4000;
const LOG_DIR = path.join(__dirname, "logs");
const LOG_FILE = path.join(LOG_DIR, "callbacks.log");
try { fs.mkdirSync(LOG_DIR, { recursive: true }); } catch (_) {}

const received = []; // 메모리 최근 내역

function nowIso() {
  return new Date().toISOString();
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
  });
}

const server = http.createServer(async (req, res) => {
  const { method, url } = req;

  if (method === "GET" && url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ status: "ok", role: "mock-callback", received_count: received.length }));
  }

  if (method === "GET" && url === "/callbacks") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ count: received.length, items: received.slice(-50) }, null, 2));
  }

  if (method === "POST" && url.startsWith("/mock-callback")) {
    const raw = await readBody(req);
    let parsed;
    try { parsed = JSON.parse(raw); } catch (_) { parsed = { _unparsed: raw }; }

    const entry = {
      received_at: nowIso(),
      auth: req.headers["authorization"] || null,
      request_id: parsed.request_id || null,
      workflow_type: parsed.workflow_type || null,
      status: parsed.status || null,
      body: parsed,
    };
    received.push(entry);

    // JSONL append (영구 저장 — callback 유실 방지)
    try { fs.appendFileSync(LOG_FILE, JSON.stringify(entry) + "\n"); } catch (e) { console.error("log write failed", e); }

    const tag = entry.status === "success" ? "✅" : entry.status === "failed" ? "❌" : "❔";
    console.log(`${tag} [${entry.received_at}] ${entry.workflow_type} / ${entry.request_id} / status=${entry.status}`);
    if (entry.status === "failed") console.log("   error:", JSON.stringify(parsed.error));

    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ ok: true, stored: true, request_id: entry.request_id }));
  }

  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found", method, url }));
});

server.listen(PORT, () => {
  console.log(`[mock-callback] listening on http://localhost:${PORT}`);
  console.log(`[mock-callback] POST /mock-callback  | GET /callbacks | GET /health`);
  console.log(`[mock-callback] logging to ${LOG_FILE}`);
});
